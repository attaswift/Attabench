//
//  BenchmarkServiceProtocol.swift
//  BenchmarkService
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation

// The protocol that this service will vend as its API.
// This file will also need to be visible to the process hosting the service.
@objc protocol BenchmarkServiceProtocol {
    func suites(_ reply: @convention(block) ([String]) -> Void)
    func benchmarks(for suite: String, reply: @convention(block) ([String]) -> Void)
    func run(_ suite: String, _ benchmark: String, _ size: Int, reply: @convention(block) (TimeInterval) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"hu.lorentey.BenchmarkService"];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BenchmarkServiceProtocol)];
     [_connectionToService resume];

Once you have a connection to the service, you can use it like this:

     [[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
         // We have received a response. Update our text field, but do it on the main thread.
         NSLog(@"Result string was: %@", aString);
     }];

 And, when you are finished with the service, clean up the connection like this:

     [_connectionToService invalidate];
*/
