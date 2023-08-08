//
//  DefaultPathObserverProtocol.swift
//  PacketTunnel
//
//  Created by pronebird on 10/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes
import NetworkExtension

protocol DefaultPathObserverProtocol {
    /// Returns current default path or `nil` if unknown yet.
    var defaultPath: NetworkPath? { get }

    /// Start observing changes to `defaultPath`.
    /// Returns cancellation token that will terminate observation either upon deallocation or upon explicit call to `invalidate()`.
    func observe(_ body: @escaping (NetworkPath) -> Void) -> DefaultPathObservation
}

protocol DefaultPathObservation {
    func invalidate()
}

protocol NetworkPath {
    var status: NetworkExtension.NWPathStatus { get }
}
