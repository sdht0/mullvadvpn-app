//
//  PingerTests.swift
//  PacketTunnelCoreTests
//
//  Created by pronebird on 11/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Network
import PacketTunnelCore
import XCTest

final class PingerTests: XCTestCase {
    func testPingingLocalhost() throws {
        let expectation = self.expectation(description: "Wait for ping reply.")
        let pinger = Pinger(identifier: 1234, eventQueue: .main)

        var sendResult: PingerSendResult?

        pinger.onEvent = { event in
            if case let .response(sender, sequenceNumber) = event, sendResult?.sequenceNumber == sequenceNumber {
                XCTAssertTrue(sender.isLoopback)
                expectation.fulfill()
            }
        }

        try pinger.openSocket(bindTo: "lo0")
        sendResult = try pinger.send(to: .loopback)

        waitForExpectations(timeout: 1)
    }
}
