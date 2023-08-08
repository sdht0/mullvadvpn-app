//
//  PingerProtocol.swift
//  PacketTunnel
//
//  Created by pronebird on 10/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Network

enum PingerEvent {
    case response(_ sender: IPAddress, _ sequenceNumber: UInt16)
    case failure(Error)
}

struct PingerSendResult {
    var sequenceNumber: UInt16
    var bytesSent: UInt16
}

protocol PingerProtocol {
    var onEvent: ((PingerEvent) -> Void)? { get set }

    func openSocket(bindTo interfaceName: String?) throws
    func closeSocket()
    func send(to address: IPv4Address) throws -> PingerSendResult
}
