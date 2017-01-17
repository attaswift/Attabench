//
//  main.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-19.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: BenchmarkServiceProtocol.self)

        // Next, set the object that the connection exports. 
        // All messages sent on the connection to this service will be sent to the exported object to handle. 
        // The connection retains the exported object.
        let exported = BenchmarkService()
        newConnection.exportedObject = exported

        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()

        // Returning true from this method tells the system that you have accepted this connection.
        // If you want to reject the connection for some reason, call invalidate on the connection and return false.
        return true
    }
}

// Create the delegate for the service.
private let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
private let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
