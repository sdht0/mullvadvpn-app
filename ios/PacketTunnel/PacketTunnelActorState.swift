//
//  PacketTunnelActorState.swift
//  PacketTunnel
//
//  Created by pronebird on 07/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension PacketTunnelActor {
    indirect enum State {
        case initial
        case starting
        case started
        case reconnecting
        case stopping
        case stopped
        case error(ErrorStateContext)
    }

    struct ErrorStateContext {
        var previousState: State
        var error: Error
    }
}

extension PacketTunnelActor.State {
    func canTransition(to newState: PacketTunnelActor.State) -> Bool {
        switch (self, newState) {
        case (.initial, .starting):
            return true

        case (.stopping, .stopped):
            return true

        case (.started, .stopping), (.started, .error), (.started, .reconnecting):
            return true

        case (.starting, .started), (.starting, .stopping), (.starting, .error):
            return true

        case (.error, .stopping), (.error, .starting), (.error, .reconnecting):
            return true

        case (.reconnecting, .started), (.reconnecting, .stopping), (.reconnecting, .error):
            return true

        default:
            return false
        }
    }

    var isReconnecting: Bool {
        if case .reconnecting = self {
            return true
        }
        return false
    }
}
