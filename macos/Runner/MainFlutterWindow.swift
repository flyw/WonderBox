import Cocoa
import FlutterMacOS
import AVFoundation
import CoreImage
import AppKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let cameraChannel = FlutterMethodChannel(
      name: "com.moefunny.wonder_box/camera",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MacOSCameraHandler.shared.register(channel: cameraChannel)

    super.awakeFromNib()
  }
}

class MacOSCameraHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  static let shared = MacOSCameraHandler()

  private var session: AVCaptureSession?
  private var videoOutput: AVCaptureVideoDataOutput?
  private let sessionQueue = DispatchQueue(label: "com.moefunny.wonder_box.cameraSessionQueue")
  private let outputQueue = DispatchQueue(label: "com.moefunny.wonder_box.cameraOutputQueue")

  private var latestSampleBuffer: CMSampleBuffer?
  private let bufferLock = NSLock()
  private var frameWaitSemaphore: DispatchSemaphore?

  func register(channel: FlutterMethodChannel) {
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "requestPermission":
        self.requestPermission(result: result)
      case "getAvailableCameras":
        self.getAvailableCameras(result: result)
      case "initializeCamera":
        let args = call.arguments as? [String: Any]
        let cameraId = args?["cameraId"] as? String
        self.initializeCamera(cameraId: cameraId, result: result)
      case "captureFrame":
        let args = call.arguments as? [String: Any]
        let outputPath = args?["outputPath"] as? String
        self.captureFrame(outputPath: outputPath, result: result)
      case "disposeCamera":
        self.disposeCamera(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if status == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    } else {
      result(status == .authorized)
    }
  }

  private func getAvailableCameras(result: @escaping FlutterResult) {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      types.append(.external)
    }
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: types,
      mediaType: .video,
      position: .unspecified
    )
    let list: [[String: Any]] = discovery.devices.map { device in
      return [
        "id": device.uniqueID,
        "name": device.localizedName,
        "isFront": device.position == .front
      ]
    }
    result(list)
  }

  private func initializeCamera(cameraId: String?, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.stopCurrentSession()

      let newSession = AVCaptureSession()
      newSession.sessionPreset = .high

      var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
      if #available(macOS 14.0, *) {
        types.append(.external)
      }
      let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: types,
        mediaType: .video,
        position: .unspecified
      )

      var selectedDevice: AVCaptureDevice?
      if let targetId = cameraId {
        selectedDevice = discovery.devices.first(where: { $0.uniqueID == targetId })
      }
      if selectedDevice == nil {
        selectedDevice = AVCaptureDevice.default(for: .video)
      }

      guard let device = selectedDevice else {
        DispatchQueue.main.async {
          result(FlutterError(code: "NO_CAMERA", message: "No video device found on macOS", details: nil))
        }
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: device)
        if newSession.canAddInput(input) {
          newSession.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: self.outputQueue)
        if newSession.canAddOutput(output) {
          newSession.addOutput(output)
        }

        newSession.startRunning()
        self.session = newSession
        self.videoOutput = output

        DispatchQueue.main.async {
          result(true)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    bufferLock.lock()
    latestSampleBuffer = sampleBuffer
    if let sema = frameWaitSemaphore {
      frameWaitSemaphore = nil
      sema.signal()
    }
    bufferLock.unlock()
  }

  private func captureFrame(outputPath: String?, result: @escaping FlutterResult) {
    guard let path = outputPath else {
      result(FlutterError(code: "INVALID_ARGS", message: "outputPath is required", details: nil))
      return
    }

    sessionQueue.async { [weak self] in
      guard let self = self else { return }

      var buffer = self.getLatestBuffer()
      if buffer == nil {
        let sema = DispatchSemaphore(value: 0)
        self.bufferLock.lock()
        self.frameWaitSemaphore = sema
        self.bufferLock.unlock()

        _ = sema.wait(timeout: .now() + 1.5)
        buffer = self.getLatestBuffer()
      }

      guard let sampleBuffer = buffer,
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "FRAME_UNAVAILABLE", message: "No frame captured from camera yet", details: nil))
        }
        return
      }

      let ciImage = CIImage(cvImageBuffer: imageBuffer)
      let context = CIContext()
      guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "RENDER_FAILED", message: "Failed to render CGImage", details: nil))
        }
        return
      }

      let rep = NSBitmapImageRep(cgImage: cgImage)
      guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "ENCODE_FAILED", message: "Failed to encode JPEG", details: nil))
        }
        return
      }

      do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpegData.write(to: url)
        DispatchQueue.main.async {
          result(path)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func getLatestBuffer() -> CMSampleBuffer? {
    bufferLock.lock()
    defer { bufferLock.unlock() }
    return latestSampleBuffer
  }

  private func stopCurrentSession() {
    if let s = session, s.isRunning {
      s.stopRunning()
    }
    session = nil
    videoOutput = nil
    bufferLock.lock()
    latestSampleBuffer = nil
    bufferLock.unlock()
  }

  private func disposeCamera(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      self?.stopCurrentSession()
      DispatchQueue.main.async {
        result(true)
      }
    }
  }
}
