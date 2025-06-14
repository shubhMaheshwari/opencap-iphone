//
//  CameraController.swift
//  OpenCap
//
//  Created by Nik on 05.09.2022.
//

import Alamofire
import AVFoundation
import SwiftUI

protocol CameraControllerDelegate: AnyObject {
    func didScanQRCode()
    func didFailedUploadingVideo(with message: String?)
    func uploadingVideoStarted()
    func uploadingVideoCanceled()
    func updateUploadingProgress(progress: Double)
    func didFinishUploadingVideo()
}

enum CameraControllerError: Swift.Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case inputsAreInvalid
    case invalidOperation
    case noCamerasAvailable
    case unknown
}

class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureFileOutputRecordingDelegate {
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var metadataOutput: AVCaptureMetadataOutput?
    var videoOutput: AVCaptureMovieFileOutput?
    var apiUrl = ""
    var sessionStatusUrl = ""
    var presignedUrl = ""
    var videoLink: String?
    var uploadVideoRequest: UploadRequest?

    var bestFormat: AVCaptureDevice.Format?
    weak var delegate: CameraControllerDelegate?
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        self.captureSession?.removeOutput(self.metadataOutput!)
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            print("String = \(stringValue)")
            let url = URL(string: stringValue)
            let domain = url?.host
            self.apiUrl = "https://" + domain!
            self.sessionStatusUrl = stringValue + "?device_id=" + UIDevice.current.identifierForVendor!.uuidString
            self.presignedUrl = stringValue.replacingOccurrences(of: "/status", with: "") + "get_presigned_url/"
            print(self.sessionStatusUrl)
            self.delegate?.didScanQRCode()
            self.setAutoFocus()
        }
    }

    func prepare(completionHandler: @escaping (Error?) -> Void) {
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }
        func configureCameraForHighestFrameRate(device: AVCaptureDevice) {
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    print(format)
                    if range.maxFrameRate > bestFrameRateRange?.maxFrameRate ?? 0 {
                        bestFormat = format
                        bestFrameRateRange = range
                    }
                }
            }
            self.bestFormat = bestFormat
            print(bestFormat)
            print(bestFrameRateRange)
            if let bestFormat = bestFormat,
               let bestFrameRateRange = bestFrameRateRange
            {
                do {
                    try device.lockForConfiguration()
                    
                    // Set the device's active format.
                    device.activeFormat = bestFormat
                    device.activeVideoMaxFrameDuration = bestFrameRateRange.minFrameDuration
                    device.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration
                    device.unlockForConfiguration()
                }
                catch {
                    print("Can't change the framerate")
                    // Handle error.
                }
            }
        }
        
        func configureCaptureDevices() throws {
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: AVMediaType.video, position: .back)

            self.frontCamera = camera
            
//            try camera?.lockForConfiguration()
            configureCameraForHighestFrameRate(device: camera!)
//            camera?.unlockForConfiguration()
        }
        
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
               
            if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!) }
                else { throw CameraControllerError.inputsAreInvalid }
                
                let metadataOutput = AVCaptureMetadataOutput()

                if captureSession.canAddOutput(metadataOutput) {
                    self.metadataOutput = AVCaptureMetadataOutput()
                    captureSession.addOutput(self.metadataOutput!)

                    self.metadataOutput!.setMetadataObjectsDelegate(self, queue: .main)
                    
                    self.metadataOutput!
                        .metadataObjectTypes = [.qr]
                    print("configured metadata")
                    
                    self.videoOutput = AVCaptureMovieFileOutput()
                    captureSession.addOutput(self.videoOutput!)
                }
                else {
                    print("Can't configure")
                }
            }
            else { throw CameraControllerError.noCamerasAvailable }
            captureSession.startRunning()
            var captureInput: AVCaptureDeviceInput? {
                return self.captureSession?.inputs.first as? AVCaptureDeviceInput
            }
            let dims: CMVideoDimensions = CMVideoFormatDescriptionGetDimensions(captureInput!.device.activeFormat.formatDescription)
            print(dims)
        }
           
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
            }
                
            catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func recordVideo(frameRate: Int32) {
        guard let frontCamera = self.frontCamera else { return }

        do {
            try frontCamera.lockForConfiguration()

            if let bestFormat = self.bestFormat {
                frontCamera.activeFormat = bestFormat
                // Set the device's min/max frame duration.
                let duration = CMTimeMake(value: 1, timescale: frameRate)
                frontCamera.activeVideoMinFrameDuration = duration
                frontCamera.activeVideoMaxFrameDuration = duration
                let durationSec = Float(CMTimeGetSeconds(duration))
                print("Duration set to " + String(format: "%.2f", durationSec))
            }
            print(frontCamera.activeFormat)

            frontCamera.unlockForConfiguration()
        }
        catch {
            print("Failed to lock configuration: \(error)")
        }

        guard let captureSession = self.captureSession, captureSession.isRunning else {
            return
        }

        let videoUrl = NSURL.fileURL(withPathComponents: [NSTemporaryDirectory(), "\(UUID().uuidString)recording.mov"])
        
        let connection = self.videoOutput!.connection(with: .video)!
       
        // enable the flag
        if #available(iOS 11.0, *), connection.isCameraIntrinsicMatrixDeliverySupported {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.off
        }

        var rotateValue = ""
        let newOrientation: AVCaptureVideoOrientation
        switch Device.currentDeviceOrientation {
        case .portrait:
            newOrientation = .portrait // 2
            rotateValue = "90"
        case .portraitUpsideDown:
            newOrientation = .portraitUpsideDown // 1
            rotateValue = "270"
        case .landscapeLeft:
            newOrientation = .landscapeRight // 4
            rotateValue = "0"
        case .landscapeRight:
            newOrientation = .landscapeLeft // 3
            rotateValue = "180"
        default:
            newOrientation = .portrait
            rotateValue = "90"
        }
        connection.videoOrientation = newOrientation

        let descriptionItem = AVMutableMetadataItem()
        descriptionItem.identifier = .quickTimeMetadataVideoOrientation
        descriptionItem.value = rotateValue as (NSCopying & NSObjectProtocol)?
        self.videoOutput!.metadata = [descriptionItem]
        
        self.videoOutput!.startRecording(to: videoUrl!, recordingDelegate: self)
        print("RECORDING STARTED: " + videoUrl!.absoluteString)
//        self.videoRecordCompletionBlock = completion
    }
    
    func getMaxFrameRate() -> Int {
        guard let frontCamera = frontCamera else { return 0 }
        var maxFrameRate: Double = 0

        for format in frontCamera.formats {
            print("Active formats are: \(format)")
            let ranges = format.videoSupportedFrameRateRanges as [AVFrameRateRange]
            let frameRates = ranges[0]
            if frameRates.maxFrameRate > maxFrameRate {
                maxFrameRate = frameRates.maxFrameRate
            }
        }
        print("MaxFrameRate = \(maxFrameRate)")
        return Int(maxFrameRate)
    }
    
    
    func stopRecording() {
        self.videoOutput?.stopRecording()
    }
    
    func stopUploadingVideo() {
        self.uploadVideoRequest?.cancel()
        self.delegate?.uploadingVideoCanceled()
    }
    
    func restartCamera() {
        if let metadataOutput = metadataOutput {
            self.captureSession?.addOutput(metadataOutput)
        }
    }
    
    func setAutoFocus() {
        do {
            try self.frontCamera?.lockForConfiguration()
        }
        catch {
            return
        }
        self.frontCamera?.focusMode = .continuousAutoFocus
        self.frontCamera?.unlockForConfiguration()
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        let connection = self.videoOutput!.connection(with: .video)!
        if #available(iOS 11.0, *), connection.isCameraIntrinsicMatrixDeliverySupported {
            if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data {
                let matrix: matrix_float3x3 = camData.withUnsafeBytes { $0.pointee }
                print(matrix)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard let frontCamera = frontCamera else { return }
        if error == nil {
            print("RECORDED")
            print("seconds = %f", CMTimeGetSeconds(frontCamera.activeVideoMaxFrameDuration))
            print("Sending: " + outputFileURL.absoluteString)
            let file = try? Data(contentsOf: outputFileURL)
            
            let videoURL = URL(string: self.apiUrl + self.videoLink!)
            
            if file != nil {
                print("Updating video: " + videoURL!.absoluteString)
                let sfov = String(self.frontCamera!.activeFormat.videoFieldOfView.description)
                
                var systemInfo = utsname()
                uname(&systemInfo)
                let modelCode = withUnsafePointer(to: &systemInfo.machine) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                        ptr in String(validatingUTF8: ptr)
                    }
                }
                let modelCodeStr = String(modelCode!)
                let maxFrameRate = self.getMaxFrameRate()
                fetchVideoCredentials { videoCredentials, error in
                    guard let videoCredentials = videoCredentials else {
                        return
                    }
                    self.uploadVideoToS3(file: file!, uploadCredentials: videoCredentials) { error in
                        if error == nil {
                            let params = ["video_url": videoCredentials.key,
                                          "parameters": ["fov": sfov,
                                                         "model": modelCodeStr,
                                                         "max_framerate": maxFrameRate]]
                            
                            AF.request(videoURL?.absoluteString ?? "", method: .patch, parameters: params, encoding: JSONEncoding.default)
                                .responseJSON { response in
                                    switch response.result {
                                    case .success(let value):
                                        print(value)
                                    case .failure(let error):
                                        print(error)
                                    }
                                }
                        }
                    }
                }
            }
        }
        else {
            print("ERROR")
        }
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
            
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.backgroundColor = appBlue.cgColor
        self.previewLayer?.videoGravity = Device.IS_IPHONE ? .resizeAspect : .resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    // MARK: - uploading to S3
    
    private func uploadVideoToS3(file: Data, uploadCredentials s3: VideoCredentials, completion: @escaping ((Error?) -> Void)) {
        let parameter = ["key": s3.key,
                         "AWSAccessKeyId": s3.accessKeyId,
                         "policy": s3.policy,
                         "signature": s3.signature]
        
        self.delegate?.uploadingVideoStarted()
        self.uploadVideoRequest = AF.upload(multipartFormData: { multipartFormData in
                                                for (key, value) in parameter {
                                                    multipartFormData.append(value.data(using: .utf8)!, withName: key)
                                                }
                                                multipartFormData.append(file, withName: "file", fileName: s3.key, mimeType: "video/mp4")
                                            },
                                            to: s3.url, method: .post, headers: nil, interceptor: RetryRequestInterceptor(retryCount: 2), requestModifier: { $0.timeoutInterval = 180.0 })
            .validate()
            .uploadProgress(closure: { progress in
                self.delegate?.updateUploadingProgress(progress: progress.fractionCompleted)
                if progress.isFinished {
                    self.delegate?.didFinishUploadingVideo()
                }
            })
            .response { response in
                if let error = response.error {
                    self.delegate?.didFailedUploadingVideo(with: "Error uploading video to S3: \(error.localizedDescription)")
                    completion(error)
                }
                else {
                    print("Successfully uploaded video to S3 \(response)")
                    completion(nil)
                }
            }
    }
}

extension CameraController {
    func fetchVideoCredentials(completion: @escaping ((VideoCredentials?, Error?) -> Void)) {
        if let url = URL(string: presignedUrl) {
            URLSession.shared.dataTask(with: url) { data, _, error in
                if let data = data {
                    do {
                        let videoCredentials = try JSONDecoder().decode(VideoCredentials.self, from: data)
                        completion(videoCredentials, nil)
                    }
                    catch {
                        print(error)
                        self.delegate?.didFailedUploadingVideo(with: "Error fetching presign URL: \(error.localizedDescription)")
                        completion(nil, error)
                    }
                }
            }.resume()
        }
    }
}
