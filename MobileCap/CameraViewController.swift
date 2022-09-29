//
//  CameraViewController.swift
//  OpenCap
//
//  Created by Nik on 05.09.2022.
//

import UIKit
import Alamofire
import SwiftUI
import SwiftMessages
import Reachability

final class CameraViewController: UIViewController {
    weak var timer: Timer?

    let cameraController = CameraController()
    var previewView: UIView!
    var previousStatus = "ready"
    var squareView: UXQRMiddleSquareView?
    var instructionView: InstructionView?
    var bottomActivityView: BottomActivityView?
    let reachability = try! Reachability()
    var connectionErrorView: MessageView?
    
    deinit {
        reachability.stopNotifier()
        NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: reachability)
    }
    
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
        
        prepareCamera()
        addInstructionView()
        addBottomActivityView()
        addSquareView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNetworkObserver()
    }
    
    func setupNetworkObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
          do{
            try reachability.startNotifier()
          }catch{
            print("could not start reachability notifier")
          }
    }
    
    func prepareCamera() {
        cameraController.prepare {(error) in
            if let error = error {
                print(error)
            }
            
            try? self.cameraController.displayPreview(on: self.previewView)
        }
    }
    
    @objc func reachabilityChanged(note: Notification) {

      let reachability = note.object as! Reachability

      switch reachability.connection {
      case .wifi:
          print("Reachable via WiFi")
          self.dismissNoInternetConnectionError()
      case .cellular:
          print("Reachable via Cellular")
          self.dismissNoInternetConnectionError()
      case .unavailable:
          self.presentNoInternetConnectionError()
        print("Network not reachable")
      }
    }
    
    func presentNoInternetConnectionError() {
        connectionErrorView = MessageView.viewFromNib(layout: .cardView)
        guard let connectionErrorView = connectionErrorView else {
            return
        }

        connectionErrorView.configureTheme(.error)
        connectionErrorView.button?.isHidden = true
        connectionErrorView.configureDropShadow()
        connectionErrorView.configureContent(title: "", body: "Device no longer connected to server, verify your internet connection")
        connectionErrorView.layoutMarginAdditions = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        (connectionErrorView.backgroundView as? CornerRoundingView)?.cornerRadius = 10
        var config = SwiftMessages.defaultConfig
        config.duration = .forever
        config.interactiveHide = false
        SwiftMessages.show(config: config, view: connectionErrorView)
    }
    
    func dismissNoInternetConnectionError() {
        SwiftMessages.hide()
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
    
    func addBottomActivityView() {
        bottomActivityView = BottomActivityView(frame: CGRect(x: 0, y: UIScreen.main.bounds.size.height-100, width: UIScreen.main.bounds.size.width, height: 100))
        bottomActivityView?.delegate = self
        
        guard let bottomActivityView = bottomActivityView else {
            return
        }
        self.view.addSubview(bottomActivityView)
    }
}

extension CameraViewController: CameraControllerDelegate {
    func didScanQRCode() {
        updateInstructionViewText()
        removeSquareView()
        removeInstructionView()
    }
}

extension CameraViewController: BottomActivityViewDelegate {
    func didTapActionButton() {
        let alert = UIAlertController(title: "", message: "Please select an option", preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
           
           alert.addAction(UIAlertAction(title: "Start a new session", style: .default , handler:{ (UIAlertAction)in
               print("User click Start a new session")
               DispatchQueue.main.async {
                   self.cameraController.sessionStatusUrl = "https://api.opencap.ai"
                   self.cameraController.setAutoFocus()
                   self.timer?.invalidate()
                   
                   let viewController = CameraViewController()
                   viewController.modalPresentationStyle = .fullScreen
                   self.present(viewController, animated: true)
               }
           }))
        
           alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler:{ (UIAlertAction)in
               print("User click Dismiss button")
           }))
        
           self.present(alert, animated: true, completion: {
               print("completion block")
           })
    }
}


