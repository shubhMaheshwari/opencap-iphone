//
//  CameraViewController.swift
//  OpenCap
//
//  Created by Nik on 05.09.2022.
//

import UIKit
import Alamofire
import SwiftUI

final class CameraViewController: UIViewController {
    weak var timer: Timer?

    let cameraController = CameraController()
    var previewView: UIView!
    var previousStatus = "ready"
    var squareView: UXQRMiddleSquareView?
    var instructionView: InstructionView?
    
    override func viewDidLoad() {
        
        cameraController.delegate = self
        UIApplication.shared.isIdleTimerDisabled = true

        let localURL = URL(fileURLWithPath: "file.txt")
        try? "Some string".write(to: localURL, atomically: true, encoding: .utf8)
                
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                      repeats: true,
                                      block: { [weak self] timer in
                                        let url = URL(string: self!.cameraController.sessionStatusUrl)!
                                                                                
         let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
             guard let data = data else { return }
            //print(String(data: data, encoding: .utf8)!)
            //print(String(self!.cameraController.sessionStatusUrl))
            
            let json = try? JSONSerialization.jsonObject(with: data, options: [])
            
            if let dictionary = json as? [String: Any] {
                if let video = dictionary["video"] as? String {
                    self!.cameraController.videoLink = video
                }
                if let lenspos = dictionary["lenspos"] as? Float {
                    self!.cameraController.lensPosition = lenspos
                }
                if let trial = dictionary["trial"] as? String {
                    self!.cameraController.trialLink = trial
                }
                if let status = dictionary["status"] as? String {
                    print(status)
                    if (self!.previousStatus != status && status == "recording")
                    {
                        var frameRate = Int32(60)
                        if let desiredFrameRate = dictionary["framerate"] as? Int32 {
                            frameRate = desiredFrameRate
                        }
                        self?.cameraController.recordVideo(frameRate: frameRate)
                    }
                    if (self!.previousStatus != status && status == "uploading")
                    {
                        self?.cameraController.stopRecording()
                    }
                    self?.previousStatus = status
                }
                if let newSession = dictionary["newSessionURL"] as? String {
                    self?.cameraController.sessionStatusUrl = newSession + "?device_id=" + UIDevice.current.identifierForVendor!.uuidString
                    print("Switched session to" + String(self!.cameraController.sessionStatusUrl))
                }
                
            }
            // if no "status" continue
            // if data["status"] == "recording" then start recording
            // if data["status"] == "uploading" then stop recording and submit the video
         }

         task.resume()
        })

        previewView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        previewView.contentMode = UIView.ContentMode.scaleAspectFit
        view.addSubview(previewView)
        
        cameraController.prepare {(error) in
            if let error = error {
                print(error)
            }
            
            try? self.cameraController.displayPreview(on: self.previewView)
        }
        
        addInstructionView()
        addSquareView()
        //cameraController.recordVideo()
    }
    
    func addSquareView() {
        squareView = UXQRMiddleSquareView(frame: CGRect.zero)
        guard let squareView = squareView else {
            return
        }
        squareView.center = self.view.center
        self.view.addSubview(squareView)
    }
    
    func removeSquareView() {
        squareView?.removeFromSuperview()
    }
    
    func addInstructionView() {
        instructionView = InstructionView(frame: CGRect.init(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height / 5))
        guard let instructionView = instructionView else {
            return
        }
        self.view.addSubview(instructionView)
    }
    
    func removeInstructionView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            self.instructionView?.removeFromSuperview()
        }
    }
    
    func updateInstructionViewText() {
        instructionView?.titleLabel?.text = InstructionTextType.mountDevice.rawValue
    }
}

extension CameraViewController : UIViewControllerRepresentable {
    public typealias UIViewControllerType = CameraViewController
    
    public func makeUIViewController(context: UIViewControllerRepresentableContext<CameraViewController>) -> CameraViewController {
        return CameraViewController()
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: UIViewControllerRepresentableContext<CameraViewController>) {
    }
}

extension CameraViewController: CameraControllerDelegate {
    func didScanQRCode() {
        updateInstructionViewText()
        removeSquareView()
        removeInstructionView()
    }
}

