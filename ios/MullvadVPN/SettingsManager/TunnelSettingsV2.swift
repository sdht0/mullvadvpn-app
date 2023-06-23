//
//  TunnelSettingsV2.swift
//  MullvadVPN
//
//  Created by pronebird on 27/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes
import struct Network.IPv4Address
import struct WireGuardKitTypes.IPAddressRange
import class WireGuardKitTypes.PrivateKey
import class WireGuardKitTypes.PublicKey

struct TunnelSettingsV2: Codable, Equatable {
    /// Relay constraints.
    var relayConstraints: RelayConstraints

    /// DNS settings.
    var dnsSettings: DNSSettings

    /// Obfuscation settings.
    /// Added in 2023.4
    var obfuscationSettings: ObfuscationSettings

    init(
        relayConstraints: RelayConstraints = RelayConstraints(),
        dnsSettings: DNSSettings = DNSSettings(),
        obfuscationSettings: ObfuscationSettings = ObfuscationSettings()
    ) {
        self.relayConstraints = relayConstraints
        self.dnsSettings = dnsSettings
        self.obfuscationSettings = obfuscationSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        relayConstraints = try container.decode(RelayConstraints.self, forKey: .relayConstraints)
        dnsSettings = try container.decode(DNSSettings.self, forKey: .dnsSettings)

        // Added in 2023.4
        obfuscationSettings = try container.decodeIfPresent(ObfuscationSettings.self, forKey: .obfuscationSettings)
            ?? ObfuscationSettings()
    }
}

struct StoredWgKeyData: Codable, Equatable {
    /// Private key creation date.
    var creationDate: Date

    /// Last date a rotation was attempted. Nil if last attempt was successful.
    var lastRotationAttemptDate: Date?

    /// Private key.
    var privateKey: PrivateKey

    /// Next private key we're trying to rotate to.
    /// Added in 2023.3
    var nextPrivateKey: PrivateKey?
}
