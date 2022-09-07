//
//  InstructionView.swift
//  OpenCap
//
//  Created by Nik on 02.09.2022.
//

import UIKit

enum InstructionTextType: String {
    case scan = "Scan QR code displayed on web app (app.opencap.ai)"
    case mountDevice = "Mount iOS device to tripod and return to web app"
}

class InstructionView: UIView {

    public var titleLabel: UILabel?
    
    override init(frame: CGRect) {

        super.init(frame:frame)

        self.backgroundColor = appBlue
        titleLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: frame.height))
        titleLabel?.text = InstructionTextType.scan.rawValue
        titleLabel?.font = UIFont.systemFont(ofSize: 25)
        titleLabel?.numberOfLines = 0
        titleLabel?.textAlignment = .center
        titleLabel?.center = self.center
        
        addSubview(titleLabel!)
        titleLabel?.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20).isActive = true
        titleLabel?.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 20).isActive = true

    }
    

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

}
