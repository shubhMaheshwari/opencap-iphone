//
//  ContentView.swift
//  MobileCap
//
//  Created by Lukasz Kidzinski on 12/12/20.
//

import SwiftUI
import AVFoundation

class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureFileOutputRecordingDelegate {
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var metadataOutput: AVCaptureMetadataOutput?
    var videoOutput: AVCaptureMovieFileOutput?
    var sessionStatusUrl = "https://mobilecap.kidzinski.com"

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.removeOutput(self.metadataOutput!)
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.sessionStatusUrl = stringValue + "?device_id=test"
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
        let fileUrl = paths[0].appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: fileUrl)
        videoOutput!.startRecording(to: fileUrl, recordingDelegate: self)
        print("RECORDING STARTED")
//        self.videoRecordCompletionBlock = completion
    }
    func stopRecording() {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
//            completion(CameraControllerError.captureSessionIsMissing)
            return
        }
        self.videoOutput?.stopRecording()
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if error == nil {
            print("Recorded")
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
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                      repeats: true,
                                      block: { [weak self] timer in
                                        let url = URL(string: self!.cameraController.sessionStatusUrl)!

         let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
             guard let data = data else { return }
             // print(String(data: data, encoding: .utf8)!)
            
            let json = try? JSONSerialization.jsonObject(with: data, options: [])
            
//            print("JSON")
            if let dictionary = json as? [String: Any] {
                print(dictionary)
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
