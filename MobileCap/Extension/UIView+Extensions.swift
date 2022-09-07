//
//  UIView+Extensions.swift
//  OpenCap
//
//  Created by Nik on 05.09.2022.
//

import UIKit

extension UIView {
    @discardableResult
    func subviewFromNib<T: UIView>() -> T? {
        guard let view = Bundle(for: type(of: self)).loadNibNamed(String(describing: type(of: self)), owner: self, options: nil)?.first as? T else {
            return nil
        }

        frame = view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)

        return view
    }
}

