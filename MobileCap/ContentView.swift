//
//  ContentView.swift
//  MobileCap
//
//  Created by Lukasz Kidzinski on 12/12/20.
//

import SwiftUI
import AVFoundation
import Alamofire

class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureFileOutputRecordingDelegate {
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var metadataOutput: AVCaptureMetadataOutput?
    var videoOutput: AVCaptureMovieFileOutput?
    var apiUrl = "https://api.mobilecap.kidzinski.com"
    var sessionStatusUrl = "https://api.mobilecap.kidzinski.com"
    var trialLink: String?
    var videoLink: String?

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.removeOutput(self.metadataOutput!)
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.sessionStatusUrl = stringValue + "?device_id=" + UIDevice.current.identifierForVendor!.uuidString
            print(self.sessionStatusUrl)
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
                    if range.maxFrameRate > bestFrameRateRange?.maxFrameRate ?? 0 {
                        bestFormat = format
                        bestFrameRateRange = range
                    }
                }
            }
            
            if let bestFormat = bestFormat,
               let bestFrameRateRange = bestFrameRateRange {
                do {
                    try device.lockForConfiguration()
                    
                    // Set the device's active format.
                    device.activeFormat = bestFormat
                    
                    // Set the device's min/max frame duration.
                    let duration = bestFrameRateRange.minFrameDuration
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    
                    device.unlockForConfiguration()
                } catch {
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
    
    func recordVideo() {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
//            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        let trialString = trialLink!.replacingOccurrences(of: "/", with: "")
        let videoUrl = paths[0].appendingPathComponent(trialString + UIDevice.current.identifierForVendor!.uuidString + ".mov")
        try? FileManager.default.removeItem(at: videoUrl)
        let connection = videoOutput!.connection(with: .video)!
        // enable the flag
        if #available(iOS 11.0, *), connection.isCameraIntrinsicMatrixDeliverySupported {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        
        videoOutput!.startRecording(to: videoUrl, recordingDelegate: self)
        print("RECORDING STARTED: " + videoUrl.absoluteString)
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
            print("Sending: " + outputFileURL.absoluteString)
            let file = try? Data(contentsOf: outputFileURL)
                
            let headers: HTTPHeaders = [
                "Content-type": "multipart/form-data"
            ]

            let videoURL = URL(string: self.apiUrl + self.videoLink!)

            if (file != nil){
                print("Updating video: " + videoURL!.absoluteString)
                let sfov = String(self.frontCamera!.activeFormat.videoFieldOfView.description)
                let parameters = Data(("{\"fov\":"+sfov+"}").utf8)
                AF.upload(
                    multipartFormData: { multipartFormData in
                        multipartFormData.append(file!, withName: "video" , fileName: "recording.mov", mimeType: "video/mp4")
                        multipartFormData.append(parameters, withName: "parameters")
                },
                    to: videoURL!, method: .patch , headers: headers)
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
            self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
}

enum CameraControllerError: Swift.Error {
   case captureSessionAlreadyRunning
   case captureSessionIsMissing
   case inputsAreInvalid
   case invalidOperation
   case noCamerasAvailable
   case unknown
}

final class CameraViewController: UIViewController {
    weak var timer: Timer?

    let cameraController = CameraController()
    var previewView: UIView!
    var previousStatus = "ready"
    
    override func viewDidLoad() {
        UIApplication.shared.isIdleTimerDisabled = true

        let localURL = URL(fileURLWithPath: "file.txt")
        try? "Some string".write(to: localURL, atomically: true, encoding: .utf8)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                      repeats: true,
                                      block: { [weak self] timer in
                                        let url = URL(string: self!.cameraController.sessionStatusUrl)!
                                                                                
         let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
             guard let data = data else { return }
             // print(String(data: data, encoding: .utf8)!)
            
            let json = try? JSONSerialization.jsonObject(with: data, options: [])
            
            print(json)
            if let dictionary = json as? [String: Any] {
                if let video = dictionary["video"] as? String {
                    self!.cameraController.videoLink = video
                }
                if let trial = dictionary["trial"] as? String {
                    self!.cameraController.trialLink = trial
                }
                if let status = dictionary["status"] as? String {
                    print(status)
                    if (self!.previousStatus != status && status == "recording")
                    {
                        self?.cameraController.recordVideo()
                    }
                    if (self!.previousStatus != status && status == "uploading")
                    {
                        self?.cameraController.stopRecording()
                    }
                    self?.previousStatus = status
                }
            }
            // if no "status" continue
            // if data["status"] == "recording" then start recording
            // if data["status"] == "uploading" then stop recording and submit the video
         }

         task.resume()
        })

        previewView = UIView(frame: CGRect(x:0, y:0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        previewView.contentMode = UIView.ContentMode.scaleAspectFit
        view.addSubview(previewView)
        
        cameraController.prepare {(error) in
            if let error = error {
                print(error)
            }
            
            try? self.cameraController.displayPreview(on: self.previewView)
        }
        cameraController.recordVideo()
    }
}

extension CameraViewController : UIViewControllerRepresentable{
    public typealias UIViewControllerType = CameraViewController
    
    public func makeUIViewController(context: UIViewControllerRepresentableContext<CameraViewController>) -> CameraViewController {
        return CameraViewController()
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: UIViewControllerRepresentableContext<CameraViewController>) {
    }
}

struct ContentView: View {

    var body: some View {
        CameraViewController()
            .edgesIgnoringSafeArea(.top)
   }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
