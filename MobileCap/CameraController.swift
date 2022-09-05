//
//  CameraController.swift
//  OpenCap
//
//  Created by Nik on 05.09.2022.
//

import SwiftUI
import AVFoundation
import Alamofire

protocol CameraControllerDelegate: AnyObject {
    func didScanQRCode()
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
    var apiUrl = "https://api.opencap.ai"
    var sessionStatusUrl = "https://api.opencap.ai"
    var trialLink: String?
    var videoLink: String?
    var lensPosition = Float(0.8)
    var bestFormat: AVCaptureDevice.Format?
    weak var delegate: CameraControllerDelegate?
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.removeOutput(self.metadataOutput!)
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            print("String = \(stringValue)")
            var url = URL(string: stringValue)
            var domain = url?.host
            self.apiUrl = "https://" + domain!
            print(domain)
            self.sessionStatusUrl = stringValue + "?device_id=" + UIDevice.current.identifierForVendor!.uuidString
            print(self.sessionStatusUrl)
            delegate?.didScanQRCode()
        }
    }

    func prepare(completionHandler: @escaping (Error?) -> Void){
        func createCaptureSession(){
            self.captureSession = AVCaptureSession()
        }
        func configureCameraForHighestFrameRate(device: AVCaptureDevice) {
            
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?


            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    print(format)
//                    if CMVideoFormatDescriptionGetDimensions(format.formatDescription).width != 3840 {
//                        continue
//                    }
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
               let bestFrameRateRange = bestFrameRateRange {
                do {
                    try device.lockForConfiguration()
                    
                    // Set the device's active format.
                    device.activeFormat = bestFormat
                    device.activeVideoMaxFrameDuration = bestFrameRateRange.minFrameDuration
                    device.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration
                    device.unlockForConfiguration()
                } catch {
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
                
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!)}
                else { throw CameraControllerError.inputsAreInvalid }
                
                let metadataOutput = AVCaptureMetadataOutput()

                if (captureSession.canAddOutput(metadataOutput)) {
                    self.metadataOutput = AVCaptureMetadataOutput()
                    captureSession.addOutput(self.metadataOutput!)

                    self.metadataOutput!.setMetadataObjectsDelegate(self, queue: .main)
                    
                    self.metadataOutput!
                        .metadataObjectTypes = [.qr]
                    print("configured metadata")
                    
                    self.videoOutput = AVCaptureMovieFileOutput()
                    captureSession.addOutput(self.videoOutput!)
                }
                else{
                    print("Can't configure")
                }
            }
            else { throw CameraControllerError.noCamerasAvailable }
            
            captureSession.startRunning()
        }
           
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
            }
                
            catch {
                DispatchQueue.main.async{
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
        do {
            try self.frontCamera?.lockForConfiguration()
        }
        catch {
            return
        }
        
        self.frontCamera?.setFocusModeLocked(lensPosition: lensPosition) {
            (time:CMTime) -> Void in
        }
        if let bestFormat = self.bestFormat {
            self.frontCamera!.activeFormat = bestFormat
            // Set the device's min/max frame duration.
            let duration = CMTimeMake(value:1,timescale:frameRate)
            self.frontCamera?.activeVideoMinFrameDuration = duration
            self.frontCamera?.activeVideoMaxFrameDuration = duration
            let durationSec =  Float(CMTimeGetSeconds(duration))
            print("Duration set to "+String(format: "%.2f", durationSec))
        }
        print(self.frontCamera?.activeFormat ?? "No camera set yet")
        

        self.frontCamera?.unlockForConfiguration()

        
        guard let captureSession = self.captureSession, captureSession.isRunning else {
//            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
//        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        let trialString = trialLink!.replacingOccurrences(of: "/", with: "")
//        let videoUrl = paths[0].appendingPathComponent(trialString + UIDevice.current.identifierForVendor!.uuidString + ".mov")
//        try? FileManager.default.removeItem(at: videoUrl)
        let videoUrl = NSURL.fileURL(withPathComponents: [ NSTemporaryDirectory(), "recording.mov"])
        let connection = videoOutput!.connection(with: .video)!
        // enable the flag
        if #available(iOS 11.0, *), connection.isCameraIntrinsicMatrixDeliverySupported {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        if (connection.isVideoStabilizationSupported) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.off;
        }
        
        videoOutput!.startRecording(to: videoUrl!, recordingDelegate: self)
        print("RECORDING STARTED: " + videoUrl!.absoluteString)
//        self.videoRecordCompletionBlock = completion
    }
    func stopRecording() {
        self.videoOutput?.stopRecording()
    }
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!){
        let connection = videoOutput!.connection(with: .video)!
        if #available(iOS 11.0, *), connection.isCameraIntrinsicMatrixDeliverySupported {
            if let camData = CMGetAttachment(sampleBuffer, key:kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut:nil) as? Data {
                let matrix: matrix_float3x3 = camData.withUnsafeBytes { $0.pointee }
                print(matrix)
            }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if error == nil {
            print("RECORDED")
            print("seconds = %f", CMTimeGetSeconds(frontCamera!.activeVideoMaxFrameDuration))
            print("Sending: " + outputFileURL.absoluteString)
            let file = try? Data(contentsOf: outputFileURL)
                
            let headers: HTTPHeaders = [
                "Content-type": "multipart/form-data"
            ]

            let videoURL = URL(string: self.apiUrl + self.videoLink!)

            if (file != nil){
                print("Updating video: " + videoURL!.absoluteString)
                let sfov = String(self.frontCamera!.activeFormat.videoFieldOfView.description)
                
                // Get the model as per https://www.zerotoappstore.com/how-to-get-iphone-device-model-swift.html
                var systemInfo = utsname()
                uname(&systemInfo)
                let modelCode = withUnsafePointer(to: &systemInfo.machine) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                        ptr in String.init(validatingUTF8: ptr)
                    }
                }
                let modelCodeStr = String(modelCode!)
                let jsonparam = "{\"fov\":"+sfov+",\"model\":\""+modelCodeStr+"\"}"
                let parameters = Data(jsonparam.utf8)
                
                AF.upload(
                    multipartFormData: { multipartFormData in
                        multipartFormData.append(file!, withName: "video" , fileName: "recording.mov", mimeType: "video/mp4")
                        multipartFormData.append(parameters, withName: "parameters")
                },
                    to: videoURL!, method: .patch , headers: headers, requestModifier: { $0.timeoutInterval = 180.0})
                    .response { response in
                        if let data = response.data{
                            print(data)
                        }
                    }
                }
        } else {
            print("ERROR")
        }
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
            
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
}
