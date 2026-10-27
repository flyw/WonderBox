import Flutter
import UIKit
import Network
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var llamaListener: NWListener?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // Keep device screen active during session to prevent unexpected suspension/locking
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
    }

    Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
      if !UIApplication.shared.isIdleTimerDisabled {
        UIApplication.shared.isIdleTimerDisabled = true
      }
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "wonderbox/screen", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "keepScreenOn" {
          UIApplication.shared.isIdleTimerDisabled = true
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      NativeTtsManager.shared.setup(messenger: controller.binaryMessenger)
    }

    // Start on-device in-process Metal inference server on 127.0.0.1:58588
    ensureServerRunning()
    
    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    ensureServerRunning()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    ensureServerRunning()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WonderboxTts") {
      NativeTtsManager.shared.setup(messenger: registrar.messenger())
    }
  }

  // MARK: - In-Process On-Device Inference Server (127.0.0.1:58588)
  func ensureServerRunning() {
    if let listener = llamaListener {
      if listener.state == .ready {
        return
      }
      listener.cancel()
      llamaListener = nil
    }
    startOnDeviceLlamaServer()
  }

  private func startOnDeviceLlamaServer() {
    do {
      let params = NWParameters.tcp
      let listener = try NWListener(using: params, on: 58588)
      self.llamaListener = listener
      
      listener.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection)
      }
      
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          print("[OnDeviceLlama] ✅ Native Metal inference server is LIVE on 127.0.0.1:58588")
        case .failed(let err):
          print("[OnDeviceLlama] ⚠️ Server failed: \(err), auto-recovering in 1s...")
          DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            self?.ensureServerRunning()
          }
        case .cancelled:
          print("[OnDeviceLlama] Server listener cancelled")
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
        connection.cancel()
        return
      }

      var currentData = accumulatedData
      if let content = content {
        currentData.append(content)
      }

      // Check for header termination in raw bytes "\r\n\r\n" to avoid UTF-8 chunk boundary splits
      let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
      if let headerRange = currentData.range(of: headerSeparator) {
        let headerData = currentData.subdata(in: 0..<headerRange.lowerBound)
        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n") {
          if line.lowercased().hasPrefix("content-length:") {
            let val = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            contentLength = Int(val) ?? 0
          }
        }

        let bodyStartIndex = headerRange.upperBound
        let bodyReceivedBytes = currentData.count - bodyStartIndex

        if bodyReceivedBytes >= contentLength {
          let bodyData = currentData.subdata(in: bodyStartIndex..<currentData.count)
          let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
          let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
          self.processHTTPRequest(firstLine: firstLine, jsonBody: bodyString, connection: connection)
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

  private func sendHTTPResponse(connection: NWConnection, statusCode: Int, contentType: String, body: String) {
    let bodyData = body.data(using: .utf8) ?? Data()
    let headers = "HTTP/1.1 \(statusCode) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n"
    var fullData = headers.data(using: .utf8) ?? Data()
    fullData.append(bodyData)
    connection.send(content: fullData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
  }

  private func processHTTPRequest(firstLine: String, jsonBody: String, connection: NWConnection) {
    if firstLine.hasPrefix("OPTIONS ") {
      let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      connection.send(content: response.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
      return
    }

    if firstLine.contains("/health") || firstLine.contains("/models") {
      let body = "{\"status\":\"ready\",\"engine\":\"ios-metal-on-device\",\"model\":\"MiniCPM-V-4.6\"}"
      sendHTTPResponse(connection: connection, statusCode: 200, contentType: "application/json", body: body)
      return
    }

    if firstLine.contains("/chat/completions") {
      handleChatCompletions(jsonString: jsonBody, connection: connection)
      return
    }

    if firstLine.contains("/v1/audio/speech") || firstLine.contains("/audio/speech") {
      handleAudioSpeech(jsonString: jsonBody, connection: connection)
      return
    }

    // Default fallback
    let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    connection.send(content: resp.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
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
      let lastMsgIndex = messages.count - 1

      for (idx, msg) in messages.enumerated() {
        let isCurrentTurn = (idx == lastMsgIndex)
        let role = msg["role"] as? String ?? "user"
        var contentText = ""
        if let str = msg["content"] as? String {
          contentText = str
        } else if let arr = msg["content"] as? [[String: Any]] {
          var hasCurrentTurnImage = false
          for item in arr {
            if let t = item["text"] as? String {
              contentText += t
            } else if let type = item["type"] as? String, type == "image_url",
                      let imgUrlObj = item["image_url"] as? [String: Any],
                      let urlStr = imgUrlObj["url"] as? String {
              if isCurrentTurn {
                var rawData: Data? = nil
                if urlStr.hasPrefix("data:image/") {
                  if let commaIdx = urlStr.firstIndex(of: ",") {
                    let b64 = String(urlStr[urlStr.index(after: commaIdx)...])
                    rawData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
                  }
                } else if urlStr.hasPrefix("file://") || urlStr.hasPrefix("/") {
                  let cleanPath = urlStr.replacingOccurrences(of: "file://", with: "")
                  rawData = try? Data(contentsOf: URL(fileURLWithPath: cleanPath))
                }

                if let raw = rawData {
                  // Resize to maxDimension 448 so MiniCPM-V runs 1 single overview slice (3x faster!)
                  imageData = resizeImageIfNeeded(raw, maxDimension: 448)
                  hasCurrentTurnImage = true
                }
              }
            }
          }
          if isCurrentTurn && hasCurrentTurnImage {
            let marker = String(cString: llama_bridge_get_media_marker())
            contentText = "\(marker)\n" + contentText
          } else if arr.contains(where: { ($0["type"] as? String) == "image_url" }) {
            contentText = "[现场画面]\n" + contentText
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
        var isClosed = false
        init(connection: NWConnection) { self.connection = connection }
        func addToken(_ t: String) { accumulated += t }
        func finish() {
          guard !isClosed else { return }
          isClosed = true
          let dict: [String: Any] = [
            "choices": [
              [
                "message": [
                  "role": "assistant",
                  "content": accumulated
                ]
              ]
            ]
          ]
          let bodyData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
          let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(bodyData.count)\r\n\r\n"
          var resp = headers.data(using: .utf8) ?? Data()
          resp.append(bodyData)
          connection.send(content: resp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
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
      var isClosed = false
      init(connection: NWConnection) { self.connection = connection }
      func sendChunk(token: String) {
        guard !isClosed else { return }
        let dict: [String: Any] = [
          "choices": [
            [
              "delta": [
                "content": token
              ]
            ]
          ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let chunk = "data: \(jsonStr)\n\n"
        connection.send(content: chunk.data(using: .utf8), completion: .contentProcessed({ error in
          if error != nil {
            self.isClosed = true
          }
        }))
      }
      func finish() {
        guard !isClosed else { return }
        isClosed = true
        let done = "data: [DONE]\n\n"
        connection.send(content: done.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
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

  private func handleAudioSpeech(jsonString: String, connection: NWConnection) {
    guard let jsonData = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
      let resp = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
      connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
      return
    }

    let input = json["input"] as? String ?? ""
    let voice = json["voice"] as? String ?? "vivian"
    let speed = json["speed"] as? Double ?? 1.0

    print("[OnDeviceTTS] 🎙️ Received /v1/audio/speech: '\(input.prefix(30))...' voice=\(voice) speed=\(speed)")

    let fileManager = FileManager.default
    var modelPath: String? = nil
    if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      let candidate = docDir.appendingPathComponent("models/qwen3_tts_0.6b/qwen3-tts-0.6b-customvoice-q4_k_m.gguf").path
      if fileManager.fileExists(atPath: candidate) {
        modelPath = candidate
      }
    }

    if let path = modelPath {
      print("[OnDeviceTTS] Found local Qwen3-TTS model: \(path)")
      let body = "{\"status\":\"model_ready\",\"model\":\"qwen3-tts-0.6b-q4\",\"voice\":\"\(voice)\",\"path\":\"\(path)\"}"
      sendHTTPResponse(connection: connection, statusCode: 200, contentType: "application/json", body: body)
    } else {
      print("[OnDeviceTTS] Local Qwen3-TTS model not found on disk")
      let body = "{\"error\":\"Qwen3-TTS 0.6B Q4 本地模型尚未下载，请在设置中下载模型或配置局域网服务地址\",\"code\":\"model_not_found\"}"
      sendHTTPResponse(connection: connection, statusCode: 503, contentType: "application/json", body: body)
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
    let q4Path = docDir.appendingPathComponent("models/minicpm_v/mmproj-model-q4.gguf").path
    let f16Path = docDir.appendingPathComponent("models/minicpm_v/mmproj-model-f16.gguf").path

    func isValidModelFile(_ p: String) -> Bool {
      guard fileManager.fileExists(atPath: p),
            let attrs = try? fileManager.attributesOfItem(atPath: p),
            let size = attrs[.size] as? UInt64,
            size > 400_000_000 else {
        return false
      }
      return true
    }

    // Clean up corrupted incomplete download if present (< 400MB)
    if fileManager.fileExists(atPath: q4Path) && !isValidModelFile(q4Path) {
      try? fileManager.removeItem(atPath: q4Path)
      print("[OnDeviceLlama] ⚠️ Removed corrupted/incomplete mmproj-model-q4.gguf")
    }

    if isValidModelFile(q4Path) {
      mmprojPath = q4Path
    } else if isValidModelFile(f16Path) {
      mmprojPath = f16Path
    } else if fileManager.fileExists(atPath: f16Path) {
      mmprojPath = f16Path
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

  /// Downsamples image to maxDimension (e.g. 448px) so MiniCPM-V-4.6 processes a single overview tile
  /// instead of slicing into multiple 2x1 tiles, achieving ~3.3x faster multimodal inference.
  private func resizeImageIfNeeded(_ data: Data, maxDimension: CGFloat = 448) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let origW = image.size.width
    let origH = image.size.height
    guard origW > maxDimension || origH > maxDimension else { return data }

    let scale = maxDimension / max(origW, origH)
    let newSize = CGSize(width: round(origW * scale), height: round(origH * scale))

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0 // 1:1 pixel representation
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let resizedImage = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }

    if let jpegData = resizedImage.jpegData(compressionQuality: 0.85) {
      print("[OnDeviceLlama] ⚡️ Resized image for accelerated ViT encode: \(Int(origW))x\(Int(origH)) -> \(Int(newSize.width))x\(Int(newSize.height)) (\(data.count / 1024)KB -> \(jpegData.count / 1024)KB)")
      return jpegData
    }
    return data
  }
}

// MARK: - Native iOS AVSpeechSynthesizer & Neural TTS Player
class NativeTtsManager: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  static let shared = NativeTtsManager()

  private let synthesizer = AVSpeechSynthesizer()
  private var audioPlayer: AVAudioPlayer?
  private var channel: FlutterMethodChannel?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func setup(messenger: FlutterBinaryMessenger) {
    if channel != nil { return }
    channel = FlutterMethodChannel(name: "wonderbox/tts", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "speak":
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        let rate = args?["rate"] as? Double ?? 0.5
        let pitch = args?["pitch"] as? Double ?? 1.0
        let lang = args?["lang"] as? String ?? "zh-CN"
        let voiceId = args?["voiceIdentifier"] as? String
        self.speak(text: text, rate: Float(rate), pitch: Float(pitch), language: lang, voiceIdentifier: voiceId)
        result(true)
      case "playAudioFile":
        let args = call.arguments as? [String: Any]
        let filePath = args?["filePath"] as? String ?? ""
        let success = self.playAudioFile(filePath: filePath)
        result(success)
      case "playAudioData":
        let args = call.arguments as? [String: Any]
        if let typedData = args?["data"] as? FlutterStandardTypedData {
          let success = self.playAudioData(data: typedData.data)
          result(success)
        } else {
          result(false)
        }
      case "getVoices":
        let voices = AVSpeechSynthesisVoice.speechVoices()
          .filter { v in
            let lang = v.language.replacingOccurrences(of: "_", with: "-").lowercased()
            return lang == "en-us" || lang.hasPrefix("en-us") || lang == "zh-cn" || lang.hasPrefix("zh-cn")
          }
          .map { v -> [String: Any] in
            var displayName = v.name
            let id = v.identifier.lowercased()
            let lowerName = v.name.lowercased()
            // Format Siri voice names clearly to match iOS Settings
            if lowerName == "voice 4" || lowerName == "声音 4" || id.contains("voice_4") || id.contains("voice4") {
              displayName = "Siri (Voice 4)"
            } else if lowerName == "voice 1" || lowerName == "声音 1" || id.contains("voice_1") {
              displayName = "Siri (Voice 1)"
            } else if lowerName == "voice 2" || lowerName == "声音 2" || id.contains("voice_2") {
              displayName = "Siri (Voice 2)"
            } else if lowerName == "voice 3" || lowerName == "声音 3" || id.contains("voice_3") {
              displayName = "Siri (Voice 3)"
            } else if lowerName == "voice 5" || lowerName == "声音 5" || id.contains("voice_5") {
              displayName = "Siri (Voice 5)"
            } else if id.contains("siri") && !lowerName.contains("siri") {
              displayName = "Siri (\(v.name))"
            }
            return [
              "identifier": v.identifier,
              "name": displayName,
              "originalName": v.name,
              "language": v.language,
              "quality": v.quality.rawValue, // 1: default, 2: enhanced, 3: premium
              "gender": v.gender.rawValue
            ]
          }
        result(voices)
      case "stop":
        self.stop()
        result(true)
      case "pause":
        self.pause()
        result(true)
      case "resume":
        self.resume()
        result(true)
      case "isSpeaking":
        let isSynthSpeaking = self.synthesizer.isSpeaking
        let isPlayerPlaying = self.audioPlayer?.isPlaying ?? false
        result(isSynthSpeaking || isPlayerPlaying)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func speak(text: String, rate: Float = 0.5, pitch: Float = 1.0, language: String = "zh-CN", voiceIdentifier: String? = nil) {
    configureAudioSession()

    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let voice = selectBestVoice(preferredId: voiceIdentifier, language: language)

    // Detect if the target voice is English and text contains Chinese
    let isEnglishVoice = voice?.language.lowercased().hasPrefix("en") ?? false
    let containsChinese = trimmed.unicodeScalars.contains { scalar in
      return (0x4E00...0x9FFF).contains(scalar.value) ||
             (0x3400...0x4DBF).contains(scalar.value) ||
             (0x20000...0x2A6DF).contains(scalar.value)
    }

    var textToSpeak = trimmed
    if isEnglishVoice && containsChinese {
      // Transliterate Chinese characters into clean Latin/Pinyin so American Siri voice speaks it fluently
      if let pinyin = trimmed.applyingTransform(.toLatin, reverse: false)?
                             .applyingTransform(.stripDiacritics, reverse: false) {
        textToSpeak = pinyin
        print("[NativeTTS] Converted Chinese text to Pinyin for English voice (\(voice?.name ?? "en")): \(textToSpeak)")
      }
    }

    let utterance = AVSpeechUtterance(string: textToSpeak)
    utterance.voice = voice
    utterance.rate = rate * AVSpeechUtteranceDefaultSpeechRate * 2.0
    utterance.pitchMultiplier = pitch
    utterance.volume = 1.0

    synthesizer.speak(utterance)
  }

  func selectBestVoice(preferredId: String?, language: String = "zh-CN") -> AVSpeechSynthesisVoice? {
    let allVoices = AVSpeechSynthesisVoice.speechVoices()

    // 1. Explicit preferred voice identifier
    if let id = preferredId, !id.isEmpty {
      if let matched = allVoices.first(where: { $0.identifier == id }) {
        print("[NativeTTS] Using explicit voice: \(matched.name) (\(matched.identifier)), quality=\(matched.quality.rawValue)")
        return matched
      }
    }

    // Quality check helpers with iOS version safety
    func isPremiumQuality(_ v: AVSpeechSynthesisVoice) -> Bool {
      if #available(iOS 16.0, *) {
        return v.quality == .premium
      }
      return false
    }

    func isEnhancedQuality(_ v: AVSpeechSynthesisVoice) -> Bool {
      return v.quality == .enhanced
    }

    func isHighFidelity(_ v: AVSpeechSynthesisVoice) -> Bool {
      return isPremiumQuality(v) || isEnhancedQuality(v)
    }

    func isSiriVoice4American(_ v: AVSpeechSynthesisVoice) -> Bool {
      let lang = v.language.replacingOccurrences(of: "_", with: "-").lowercased()
      guard lang == "en-us" || lang.hasPrefix("en-us") else { return false }
      let name = v.name.lowercased()
      let id = v.identifier.lowercased()
      let is4 = name.contains("voice 4") || name.contains("声音 4") || name.contains("voice4") ||
                id.contains("voice_4") || id.contains("voice4") || id.contains("voice-4") ||
                ((name.contains("siri") || id.contains("siri")) && (name.contains("4") || id.contains("4")))
      return is4
    }

    func isFemaleVoice(_ v: AVSpeechSynthesisVoice) -> Bool {
      let id = v.identifier.lowercased()
      let name = v.name.lowercased()
      return v.gender == .female ||
             id.contains("female") ||
             id.contains("ting-ting") ||
             id.contains("tingting") ||
             id.contains("yushu") ||
             id.contains("yu-shu") ||
             id.contains("meijia") ||
             id.contains("mei-jia") ||
             id.contains("sinji") ||
             id.contains("sin-ji") ||
             name.contains("女") ||
             name.contains("婷婷") ||
             name.contains("雨舒") ||
             name.contains("美佳") ||
             name.contains("善芝") ||
             name.contains("声音 2") ||
             name.contains("voice 2")
    }

    func isSiriVoice(_ v: AVSpeechSynthesisVoice) -> Bool {
      return v.name.localizedCaseInsensitiveContains("siri") ||
             v.identifier.localizedCaseInsensitiveContains("siri")
    }

    // Diagnostic dump to captures directory
    if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let dumpDir = docDir.appendingPathComponent("captures")
      try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true, attributes: nil)
      let dumpPath = dumpDir.appendingPathComponent("installed_voices.txt")
      let lines = allVoices.map { "Name: \($0.name) | ID: \($0.identifier) | Quality: \($0.quality.rawValue) | Gender: \($0.gender.rawValue) | Lang: \($0.language)" }.joined(separator: "\n")
      try? lines.write(to: dumpPath, atomically: true, encoding: .utf8)
    }

    // Priority 0: Siri Voice 4 American (Top user choice)
    if let v = allVoices.first(where: { isSiriVoice4American($0) }) {
      print("[NativeTTS] Priority 0 - Selected Siri Voice 4 American: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 0.5: Any other English US Siri voice (e.g. Aaron / Nicky / Voice 1)
    if let v = allVoices.first(where: {
      let lang = $0.language.replacingOccurrences(of: "_", with: "-").lowercased()
      return (lang == "en-us" || lang.hasPrefix("en-us")) && isSiriVoice($0) && isHighFidelity($0)
    }) {
      print("[NativeTTS] Priority 0.5 - Selected English US Siri High-Fidelity: \(v.name) (\(v.identifier))")
      return v
    }

    let zhVoices = allVoices.filter {
      let lang = $0.language.replacingOccurrences(of: "_", with: "-").lowercased()
      return lang == "zh-cn" || lang.hasPrefix("zh-cn")
    }

    // Priority 1: Siri Female High-Fidelity (.premium / .enhanced)
    if let v = zhVoices.first(where: { isSiriVoice($0) && isFemaleVoice($0) && isHighFidelity($0) }) {
      print("[NativeTTS] Priority 1 - Selected Siri Female High-Fidelity: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 2: Siri Female (any quality)
    if let v = zhVoices.first(where: { isSiriVoice($0) && isFemaleVoice($0) }) {
      print("[NativeTTS] Priority 2 - Selected Siri Female: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 3: Any Siri High-Fidelity
    if let v = zhVoices.first(where: { isSiriVoice($0) && isHighFidelity($0) }) {
      print("[NativeTTS] Priority 3 - Selected Siri High-Fidelity: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 4: Any Siri
    if let v = zhVoices.first(where: { isSiriVoice($0) }) {
      print("[NativeTTS] Priority 4 - Selected Siri: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 5: Female zh-CN Premium (e.g. Tingting / Yushu Premium)
    if let v = zhVoices.first(where: { isFemaleVoice($0) && isPremiumQuality($0) && $0.language.lowercased().contains("cn") }) {
      print("[NativeTTS] Priority 5 - Selected Premium Female zh-CN: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 6: Female zh-CN Enhanced (e.g. Tingting / Yushu Enhanced)
    if let v = zhVoices.first(where: { isFemaleVoice($0) && isEnhancedQuality($0) && $0.language.lowercased().contains("cn") }) {
      print("[NativeTTS] Priority 6 - Selected Enhanced Female zh-CN: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 7: Natural soft female voices (Yu-shu, Mei-Jia)
    if let v = zhVoices.first(where: {
      isFemaleVoice($0) && ($0.identifier.localizedCaseInsensitiveContains("yushu") || $0.identifier.localizedCaseInsensitiveContains("yu-shu") || $0.identifier.localizedCaseInsensitiveContains("meijia") || $0.identifier.localizedCaseInsensitiveContains("mei-jia"))
    }) {
      print("[NativeTTS] Priority 7 - Selected Natural Soft Female: \(v.name) (\(v.identifier))")
      return v
    }

    // Priority 8: Any Female zh voice
    if let v = zhVoices.first(where: { isFemaleVoice($0) }) {
      print("[NativeTTS] Priority 8 - Selected Female fallback: \(v.name) (\(v.identifier))")
      return v
    }

    // 9. Fallback: strictly en-US or zh-CN
    let fallback = AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "zh-CN")
    print("[NativeTTS] Final Fallback voice: \(fallback?.name ?? "default")")
    return fallback
  }

  func playAudioFile(filePath: String) -> Bool {
    configureAudioSession()
    stop()
    let fileUrl = URL(fileURLWithPath: filePath)
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: fileUrl)
      audioPlayer?.delegate = self
      audioPlayer?.prepareToPlay()
      let started = audioPlayer?.play() ?? false
      if started {
        channel?.invokeMethod("onStart", arguments: nil)
      }
      return started
    } catch {
      print("[NativeTTS] Failed to play audio file: \(error)")
      return false
    }
  }

  func playAudioData(data: Data) -> Bool {
    configureAudioSession()
    stop()
    do {
      audioPlayer = try AVAudioPlayer(data: data)
      audioPlayer?.delegate = self
      audioPlayer?.prepareToPlay()
      let started = audioPlayer?.play() ?? false
      if started {
        channel?.invokeMethod("onStart", arguments: nil)
      }
      return started
    } catch {
      print("[NativeTTS] Failed to play audio data: \(error)")
      return false
    }
  }

  func stop() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    if let player = audioPlayer, player.isPlaying {
      player.stop()
      audioPlayer = nil
      channel?.invokeMethod("onComplete", arguments: nil)
    }
  }

  func pause() {
    if synthesizer.isSpeaking {
      synthesizer.pauseSpeaking(at: .immediate)
    }
    if let player = audioPlayer, player.isPlaying {
      player.pause()
    }
  }

  func resume() {
    if synthesizer.isPaused {
      synthesizer.continueSpeaking()
    }
    if let player = audioPlayer, !player.isPlaying {
      player.play()
    }
  }

  private func configureAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      print("[NativeTTS] Failed to configure AVAudioSession: \(error)")
    }
  }

  // MARK: - AVSpeechSynthesizerDelegate
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    channel?.invokeMethod("onStart", arguments: nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    channel?.invokeMethod("onComplete", arguments: nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    channel?.invokeMethod("onCancel", arguments: nil)
  }

  // MARK: - AVAudioPlayerDelegate
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    audioPlayer = nil
    channel?.invokeMethod("onComplete", arguments: nil)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    audioPlayer = nil
    channel?.invokeMethod("onComplete", arguments: nil)
  }
}
