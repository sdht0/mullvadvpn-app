//
//  Actor.swift
//  PacketTunnel
//
//  Created by pronebird on 30/06/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadLogging
import MullvadTypes
import WireGuardKit
import RelaySelector
import TunnelProviderMessaging
import RelayCache
import NetworkExtension

actor PacketTunnelActor {
    enum State: Comparable, Equatable {
        case initial
        case starting
        case started
        case stopping
        case stopped
    }

    private var state: State = .initial

    private let providerLogger: Logger
    private let tunnelLogger: Logger

    private let adapter: WireGuardAdapter
    private let relayCache = RelayCache(cacheDirectory: ApplicationConfiguration.containerURL)
    private var startTask: Task<Void, Error>?

    var selectorResult: RelaySelectorResult?

    init(providerLogger: Logger, tunnelLogger: Logger, packetTunnelProvider: NEPacketTunnelProvider) {
        self.providerLogger = providerLogger
        self.tunnelLogger = tunnelLogger

        adapter = WireGuardAdapter(
            with: packetTunnelProvider,
            shouldHandleReasserting: false,
            logHandler: { logLevel, message in
                tunnelLogger.log(level: logLevel.loggerLevel, "\(message)")
            })
    }

    func start(options: [String: NSObject]?) async throws {
        guard state == .initial else { return }

        state = .starting

        let parsedOptions = parseStartOptions(options ?? [:])
        providerLogger.debug("\(parsedOptions.logFormat())")

        startTask = Task {
            do {
                try await startTunnel(options: parsedOptions)
            } catch {
                providerLogger.error(error: error, message: "Failed to start the tunnel.")
                providerLogger.debug("Starting an empty tunnel.")

                try await startEmptyTunnel()
            }
        }

        try await startTask?.value
    }

    private func startTunnel(options: StartOptions) async throws {
        let selectedRelay: NextRelay = options.selectorResult.map { .set($0) } ?? .automatic
        let configuration = try makeConfiguration(selectedRelay)

        try await adapter.start(tunnelConfiguration: configuration.wgTunnelConfig)
    }

    private func startEmptyTunnel() async throws {
        let emptyTunnelConfiguration = TunnelConfiguration(
            name: nil,
            interface: InterfaceConfiguration(privateKey: PrivateKey()),
            peers: []
        )

        try await adapter.start(tunnelConfiguration: emptyTunnelConfiguration)
    }

    func stop() async throws {
        guard state < .stopping else { return }

        state = .stopping
        startTask?.cancel()

        defer { state = .stopped }
        try await adapter.stop()
    }

    func handleAppMessage(_ messageData: Data) async throws -> Data? {
        let message = try TunnelProviderMessage(messageData: messageData)

        providerLogger.trace("Received app message: \(message)")

        return nil
    }

    // MARK: - Private

    private func parseStartOptions(_ options: [String: NSObject]) -> StartOptions {
        let tunnelOptions = PacketTunnelOptions(rawOptions: options)
        var parsedOptions = StartOptions(launchSource: tunnelOptions.isOnDemand() ? .onDemand : .app)

        do {
            if let selectorResult = try tunnelOptions.getSelectorResult() {
                parsedOptions.launchSource = .app
                parsedOptions.selectorResult = selectorResult
            } else {
                parsedOptions.launchSource = tunnelOptions.isOnDemand() ? .onDemand : .system
            }
        } catch {
            providerLogger.error(error: error, message: "Failed to decode relay selector result passed from the app.")
        }

        return parsedOptions
    }

    private func makeConfiguration(_ nextRelay: NextRelay) throws -> PacketTunnelConfiguration {
        let tunnelSettings = try SettingsManager.readSettings()
        let selectorResult: RelaySelectorResult

        let deviceState = try SettingsManager.readDeviceState()

        switch nextRelay {
        case .automatic:
            selectorResult = try selectRelayEndpoint(relayConstraints: tunnelSettings.relayConstraints)
        case let .set(aSelectorResult):
            selectorResult = aSelectorResult
        }

        return PacketTunnelConfiguration(
            deviceState: deviceState,
            tunnelSettings: tunnelSettings,
            selectorResult: selectorResult
        )
    }

    /// Load relay cache with potential networking to refresh the cache and pick the relay for the
    /// given relay constraints.
    private func selectRelayEndpoint(relayConstraints: RelayConstraints) throws -> RelaySelectorResult {
        let cachedRelayList = try relayCache.read()

        return try RelaySelector.evaluate(
            relays: cachedRelayList.relays,
            constraints: relayConstraints,
            numberOfFailedAttempts: packetTunnelStatus.numberOfFailedAttempts
        )
    }

}

enum LaunchSource: String, CustomStringConvertible {
    case app, onDemand, system

    var description: String {
        switch self {
        case .app, .system:
            return rawValue
        case .onDemand:
            return "on-demand rule"
        }
    }
}

struct StartOptions {
    var launchSource: LaunchSource
    var selectorResult: RelaySelectorResult?

    func logFormat() -> String {
        var s = "Start the tunnel via \(launchSource)"
        if let selectorResult {
            s.append(", connect to \(selectorResult.relay.hostname)")
        }
        s.append(".")
        return s
    }
}
