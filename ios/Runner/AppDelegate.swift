import Flutter
import UIKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var llamaListener: NWListener?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // Start on-device in-process Metal inference server on 127.0.0.1:58588
    startOnDeviceLlamaServer()
    
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - In-Process On-Device Inference Server (127.0.0.1:58588)
  private func startOnDeviceLlamaServer() {
    do {
      let params = NWParameters.tcp
      let listener = try NWListener(using: params, on: 58588)
      self.llamaListener = listener
      
      listener.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection)
      }
      
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          print("[OnDeviceLlama] ✅ Native Metal inference server is LIVE on 127.0.0.1:58588")
        case .failed(let err):
          print("[OnDeviceLlama] Server failed: \(err)")
        default:
          break
        }
      }
      
      listener.start(queue: .global(qos: .userInitiated))
    } catch {
      print("[OnDeviceLlama] Failed to create listener: \(error)")
    }
  }

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: .global(qos: .userInitiated))
    readHTTPRequest(connection: connection, accumulatedData: Data())
  }

  private func readHTTPRequest(connection: NWConnection, accumulatedData: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
      guard let self = self else { return }
      if let error = error {
        print("[OnDeviceLlama] Connection error: \(error)")
        connection.cancel()
        return
      }

      var currentData = accumulatedData
      if let content = content {
        currentData.append(content)
      }

      guard let requestString = String(data: currentData, encoding: .utf8) else {
        if isComplete { connection.cancel() }
        return
      }

      // Check if full HTTP header received
      if let headerEndRange = requestString.range(of: "\r\n\r\n") {
        let headers = String(requestString[..<headerEndRange.lowerBound])
        var contentLength = 0
        for line in headers.components(separatedBy: "\r\n") {
          if line.lowercased().hasPrefix("content-length:") {
            let val = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            contentLength = Int(val) ?? 0
          }
        }

        let bodyStartIndex = requestString.utf8.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
        let bodyReceivedBytes = currentData.count - bodyStartIndex

        if bodyReceivedBytes >= contentLength {
          let bodyString = String(requestString[headerEndRange.upperBound...])
          self.processHTTPRequest(firstLine: headers.components(separatedBy: "\r\n").first ?? "", jsonBody: bodyString, connection: connection)
        } else if isComplete {
          connection.cancel()
        } else {
          self.readHTTPRequest(connection: connection, accumulatedData: currentData)
        }
      } else if isComplete {
        connection.cancel()
      } else {
        self.readHTTPRequest(connection: connection, accumulatedData: currentData)
      }
    }
  }

  private func processHTTPRequest(firstLine: String, jsonBody: String, connection: NWConnection) {
    if firstLine.hasPrefix("OPTIONS ") {
      let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
      return
    }

    if firstLine.contains("/health") || firstLine.contains("/models") {
      let body = "{\"status\":\"ready\",\"engine\":\"ios-metal-on-device\",\"model\":\"MiniCPM-V-4.6\"}"
      let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
      connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
      return
    }

    if firstLine.contains("/chat/completions") {
      handleChatCompletions(jsonString: jsonBody, connection: connection)
      return
    }

    // Default fallback
    let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
  }

  private func handleChatCompletions(jsonString: String, connection: NWConnection) {
    // Parse JSON
    guard let jsonData = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
      let resp = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
      connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
      return
    }

    // Ensure model is loaded in Metal memory
    ensureModelLoaded()

    let isStream = json["stream"] as? Bool ?? true
    let maxTokens = json["max_tokens"] as? Int ?? 256

    // Extract prompt and optional multimodal image from messages
    var prompt = ""
    var imageData: Data? = nil

    if let messages = json["messages"] as? [[String: Any]] {
      // Find the index of the latest message that contains an image
      var lastImageIndex = -1
      for (idx, msg) in messages.enumerated() {
        if let arr = msg["content"] as? [[String: Any]] {
          if arr.contains(where: { ($0["type"] as? String) == "image_url" }) {
            lastImageIndex = idx
          }
        }
      }

      for (idx, msg) in messages.enumerated() {
        let role = msg["role"] as? String ?? "user"
        var contentText = ""
        if let str = msg["content"] as? String {
          contentText = str
        } else if let arr = msg["content"] as? [[String: Any]] {
          var hasImageInMsg = false
          for item in arr {
            if let t = item["text"] as? String {
              contentText += t
            } else if let type = item["type"] as? String, type == "image_url",
                      let imgUrlObj = item["image_url"] as? [String: Any],
                      let urlStr = imgUrlObj["url"] as? String {
              if idx == lastImageIndex {
                if urlStr.hasPrefix("data:image/") {
                  if let commaIdx = urlStr.firstIndex(of: ",") {
                    let b64 = String(urlStr[urlStr.index(after: commaIdx)...])
                    if let decoded = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                      imageData = decoded
                      hasImageInMsg = true
                    }
                  }
                } else if urlStr.hasPrefix("file://") || urlStr.hasPrefix("/") {
                  let cleanPath = urlStr.replacingOccurrences(of: "file://", with: "")
                  if let data = try? Data(contentsOf: URL(fileURLWithPath: cleanPath)) {
                    imageData = data
                    hasImageInMsg = true
                  }
                }
              }
            }
          }
          if hasImageInMsg && idx == lastImageIndex {
            let marker = String(cString: llama_bridge_get_media_marker())
            contentText = "\(marker)\n" + contentText
          } else if arr.contains(where: { ($0["type"] as? String) == "image_url" }) {
            contentText = "[历史现场画面]\n" + contentText
          }
        }
        prompt += "<|im_start|>\(role)\n\(contentText)<|im_end|>\n"
      }
      prompt += "<|im_start|>assistant\n"
    } else {
      prompt = "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n"
    }

    let imgBytes = (imageData as NSData?)?.bytes
    let imgCount = imageData?.count ?? 0

    if !isStream {
      // Non-streaming response: accumulate tokens and return JSON
      class NonStreamContext {
        let connection: NWConnection
        var accumulated = ""
        init(connection: NWConnection) { self.connection = connection }
        func addToken(_ t: String) { accumulated += t }
        func finish() {
          let escaped = accumulated
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
          let body = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"\(escaped)\"}}]}"
          let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
          connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            self.connection.cancel()
          }))
        }
      }

      let nonStreamCtx = NonStreamContext(connection: connection)
      let userPtr = Unmanaged.passRetained(nonStreamCtx).toOpaque()

      DispatchQueue.global(qos: .userInitiated).async {
        llama_bridge_generate(prompt, imgBytes, imgCount, Int32(maxTokens), { tokenPtr, isDone, uData in
          guard let uData = uData else { return }
          let ctx = Unmanaged<NonStreamContext>.fromOpaque(uData).takeUnretainedValue()
          if isDone {
            ctx.finish()
            _ = Unmanaged<NonStreamContext>.fromOpaque(uData).takeRetainedValue()
          } else if let tokenPtr = tokenPtr, let str = String(validatingUTF8: tokenPtr) {
            ctx.addToken(str)
          }
        }, userPtr)
      }
      return
    }

    // Streaming response: send SSE events
    let sseHeader = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
    connection.send(content: sseHeader.data(using: .utf8), completion: .contentProcessed({ _ in }))

    class StreamContext {
      let connection: NWConnection
      init(connection: NWConnection) { self.connection = connection }
      func sendChunk(token: String) {
        let escaped = token
          .replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "\"", with: "\\\"")
          .replacingOccurrences(of: "\n", with: "\\n")
          .replacingOccurrences(of: "\r", with: "\\r")
        let chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"\(escaped)\"}}]}\n\n"
        connection.send(content: chunk.data(using: .utf8), completion: .contentProcessed({ _ in }))
      }
      func finish() {
        let done = "data: [DONE]\n\n"
        connection.send(content: done.data(using: .utf8), completion: .contentProcessed({ _ in
          self.connection.cancel()
        }))
      }
    }

    let streamCtx = StreamContext(connection: connection)
    let userPtr = Unmanaged.passRetained(streamCtx).toOpaque()

    DispatchQueue.global(qos: .userInitiated).async {
      llama_bridge_generate(prompt, imgBytes, imgCount, Int32(maxTokens), { tokenPtr, isDone, uData in
        guard let uData = uData else { return }
        let ctx = Unmanaged<StreamContext>.fromOpaque(uData).takeUnretainedValue()
        if isDone {
          ctx.finish()
          _ = Unmanaged<StreamContext>.fromOpaque(uData).takeRetainedValue()
        } else if let tokenPtr = tokenPtr, let str = String(validatingUTF8: tokenPtr), !str.isEmpty {
          ctx.sendChunk(token: str)
        }
      }, userPtr)
    }
  }

  private func ensureModelLoaded() {
    let fileManager = FileManager.default
    guard let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

    // Check candidate paths: MiniCPM-V-4.6 or Jev-Style-0.8B
    let candidates = [
      docDir.appendingPathComponent("models/minicpm_v/MiniCPM-V-4_6-Q4_K_M.gguf").path,
      docDir.appendingPathComponent("models/jev_style/Jev-Style-0.8B-Decision-v3-Q4_K_M.gguf").path,
    ]

    let mmprojCandidates = [
      docDir.appendingPathComponent("models/minicpm_v/mmproj-model-q4.gguf").path,
      docDir.appendingPathComponent("models/minicpm_v/mmproj-model-f16.gguf").path,
    ]

    var mmprojPath: String? = nil
    for mPath in mmprojCandidates {
      if fileManager.fileExists(atPath: mPath) {
        mmprojPath = mPath
        break
      }
    }

    if llama_bridge_is_loaded() {
      // If loaded but missing vision while mmproj is present, reload with vision
      if mmprojPath != nil && !llama_bridge_has_vision() {
        print("[OnDeviceLlama] Model loaded without vision, reloading with projector: \(mmprojPath!)")
      } else {
        return
      }
    }

    for path in candidates {
      if fileManager.fileExists(atPath: path) {
        print("[OnDeviceLlama] Loading model into Apple Metal memory from: \(path)")
        if path.contains("minicpm_v") && mmprojPath != nil {
          print("[OnDeviceLlama] Attaching vision projector: \(mmprojPath!)")
          _ = llama_bridge_load_model(path, mmprojPath!, 99, 3072)
        } else {
          _ = llama_bridge_load_model(path, nil, 99, 2048)
        }
        return
      }
    }

    print("[OnDeviceLlama] No local model found in Documents directory yet")
  }
}
