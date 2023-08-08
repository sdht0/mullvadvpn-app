//
//  TunnelAdapterProtocol.swift
//  PacketTunnelCore
//
//  Created by pronebird on 08/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import WireGuardKitTypes

protocol TunnelAdapterProtocol {
    func start(configuration: TunnelConfiguration) async throws
    func stop() async throws
    func update(configuration: TunnelConfiguration) async throws
}
