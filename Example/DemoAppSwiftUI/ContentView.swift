//
//  ContentView.swift
//  DemoApp
//
//  Created by Coralogix DEV TEAM on 05/05/2024.
//

import SwiftUI
import Coralogix

struct ContentView: View {
    @Binding var coralogixRum: CoralogixRum
    let items = [Keys.failureNetworkRequest.rawValue,
                 Keys.succesfullNetworkRequest.rawValue,
                 Keys.succesfullNetworkRequestFlutter.rawValue,
                 Keys.failureNetworkRequestFlutter.rawValue,
                 Keys.sendNSException.rawValue,
                 Keys.sendNSError.rawValue,
                 Keys.sendErrorString.rawValue,
                 Keys.sendLogWithData.rawValue,
                 Keys.sendCrash.rawValue,
                 Keys.shutDownCoralogixRum.rawValue,
                 Keys.updateLabels.rawValue,
                 Keys.maskUI.rawValue]
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
                    .onAppear {
                        let userContext = UserContext(userId: "1234",
                                                      userName: "Daffy Duck",
                                                      userEmail: "daffy.duck@coralogix.com",
                                                      userMetadata: ["age": "18", "profession" : "duck"])
                        coralogixRum.setUserContext(userContext: userContext)
                    }.padding(10)
                    .border(.gray)

                NavigationLink(destination: SecondView(coralogixRum: $coralogixRum)) {
                                    Text("Go to Second View")
                                }
                                .navigationTitle("Main View")
                                .trackCXView(name: "Main View")
                                .trackCXTapAction(name: "second View")
                
                NavigationLink(destination: MaskDemoView()) {
                    Text("UI Mask Demo")
                }
                .navigationTitle("UI Mask Demo")
                
                List(items, id: \.self) { item in
                    CustomButton(item: item, coralogixRum: $coralogixRum)
                }
            }
            .padding()
        }
    }
}

struct SecondView: View {
    @Binding var coralogixRum: CoralogixRum
    
    let items = ["Send NSError",
                 "Send Crash"]
    var body: some View {
        Text("Welcome to the Second View!")
            .navigationTitle("Second View")
            .trackCXView(name: "Second View")
        
//        List(items, id: \.self) { item in
//            Button(action: {
//                print("Clicked on: \(item)")
//                if item == "Send Crash" {
//                    CrashSim.simulateRandomCrash()
//                } else if item == "Send NSError" {
//                    ErrorSim.sendNSError(cxRum: self.coralogixRum)
//                }
//            },label: {
//               Text(item)
//            }).trackCXTapAction(name: "\(item)")
//        }
//        .padding()
    }
}

struct CustomButton: View {
    var item: String
    @Binding var coralogixRum: CoralogixRum
    
    var body: some View {
        Button(action: {
            print("Clicked on: \(item)")
            if item == Keys.failureNetworkRequest.rawValue {
                NetworkSim.failureNetworkRequest()
            } else if item == Keys.succesfullNetworkRequest.rawValue {
                NetworkSim.sendSuccesfullRequest()
            } else if item == Keys.sendNSException.rawValue {
                ErrorSim.sendNSException()
            } else if item == Keys.sendNSError.rawValue {
                ErrorSim.sendNSError()
            } else if item == Keys.sendErrorString.rawValue {
                ErrorSim.sendStringError()
            } else if item == Keys.sendCrash.rawValue {
                CrashSim.simulateRandomCrash()
            } else if item == Keys.shutDownCoralogixRum.rawValue {
                coralogixRum.shutdown()
            } else if item == Keys.sendLogWithData.rawValue {
                ErrorSim.sendLog()
            } else if item == Keys.updateLabels.rawValue {
                coralogixRum.set(labels: ["item3" : "playstation 4", "itemPrice" : 400])
            } else if item == Keys.succesfullNetworkRequestFlutter.rawValue {
                NetworkSim.setNetworkRequestContextSuccsess()
            } else if item == Keys.failureNetworkRequestFlutter.rawValue {
                NetworkSim.setNetworkRequestContextFailure()
            } 
        }, label: {
            Text(item)
        }).trackCXTapAction(name: "\(item)")
    }
}
