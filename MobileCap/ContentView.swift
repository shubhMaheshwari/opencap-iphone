//
//  ContentView.swift
//  MobileCap
//
//  Created by Lukasz Kidzinski on 12/12/20.
//

import SwiftUI
import AVFoundation
import Alamofire

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
