//
//  ContentView.swift
//  MobileCap
//
//  Created by Lukasz Kidzinski on 12/12/20.
//

import SwiftUI
import AVFoundation

class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var metadataOutput: AVCaptureMetadataOutput?

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.removeOutput(self.metadataOutput!)
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            print(stringValue)
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
                    print("configured")
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
    
    let cameraController = CameraController()
    var previewView: UIView!
    
    override func viewDidLoad() {
                    
        previewView = UIView(frame: CGRect(x:0, y:0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        previewView.contentMode = UIView.ContentMode.scaleAspectFit
        view.addSubview(previewView)
        
        cameraController.prepare {(error) in
            if let error = error {
                print(error)
            }
            
            try? self.cameraController.displayPreview(on: self.previewView)
        }
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
    let timer = Timer.publish(every: 1,
                              tolerance: 0.5,
                              on: .main, in: .common).autoconnect()

    var body: some View {
        CameraViewController()
            .edgesIgnoringSafeArea(.top)
            .onReceive(timer) { time in
                let url = URL(string: "https://mobilecap.kidzinski.com")!

/*                let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
                    guard let data = data else { return }
                    print(String(data: data, encoding: .utf8)!)
                }

                task.resume()*/
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
