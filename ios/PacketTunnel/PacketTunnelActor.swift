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
import NetworkExtension
import RelayCache
import RelaySelector
import TunnelProviderMessaging
import WireGuardKit

actor PacketTunnelActor {
    enum State: Comparable, Equatable {
        case initial
        case starting
        case started
        case stopping
        case stopped
    }

    private var state: State = .initial
    private var isNetworkReachable = true
    private var numberOfFailedAttempts: UInt = 0

    private let providerLogger: Logger
    private let tunnelLogger: Logger

    private let adapter: WireGuardAdapter
    private let tunnelMonitor: TunnelMonitor
    private let relayCache = RelayCache(cacheDirectory: ApplicationConfiguration.containerURL)

    private var startTask: Task<Void, Error>?
    private var reconnectTask: Task<Void, Error>?

    private weak var packetTunnelProvider: NEPacketTunnelProvider?

    var selectorResult: RelaySelectorResult?

    init(providerLogger: Logger, tunnelLogger: Logger, packetTunnelProvider: NEPacketTunnelProvider) {
        self.providerLogger = providerLogger
        self.tunnelLogger = tunnelLogger
        self.packetTunnelProvider = packetTunnelProvider

        adapter = WireGuardAdapter(
            with: packetTunnelProvider,
            shouldHandleReasserting: false,
            logHandler: { logLevel, message in
                tunnelLogger.log(level: logLevel.loggerLevel, "\(message)")
            }
        )

        tunnelMonitor = TunnelMonitor(
            delegateQueue: .main,
            packetTunnelProvider: packetTunnelProvider,
            adapter: adapter
        )
        tunnelMonitor.delegate = self
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
                try Task.checkCancellation()

                providerLogger.error(error: error, message: "Failed to start the tunnel.")
                providerLogger.debug("Starting an empty tunnel.")

                try await startEmptyTunnel()
            }
        }

        try await startTask?.value
    }

    func stop() async throws {
        guard state < .stopping else { return }

        state = .stopping

        tunnelMonitor.stop()

        startTask?.cancel()
        reconnectTask?.cancel()

        try? await startTask?.value
        try? await reconnectTask?.value

        defer { state = .stopped }
        try await adapter.stop()
    }

    func reconnect(to nextRelay: NextRelay) async throws {
        try await reconnectTunnel(to: nextRelay, stopTunnelMonitor: true)
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
        let deviceState = try SettingsManager.readDeviceState()

        let selectorResult: RelaySelectorResult
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
        return try RelaySelector.evaluate(
            relays: relayCache.read().relays,
            constraints: relayConstraints,
            numberOfFailedAttempts: numberOfFailedAttempts
        )
    }

    private func startTunnel(options: StartOptions) async throws {
        let selectedRelay: NextRelay = options.selectorResult.map { .set($0) } ?? .automatic
        let configuration = try makeConfiguration(selectedRelay)

        try await adapter.start(tunnelConfiguration: configuration.wgTunnelConfig)
        selectorResult = configuration.selectorResult
    }

    private func startEmptyTunnel() async throws {
        let emptyTunnelConfiguration = TunnelConfiguration(
            name: nil,
            interface: InterfaceConfiguration(privateKey: PrivateKey()),
            peers: []
        )

        try await adapter.start(tunnelConfiguration: emptyTunnelConfiguration)
    }

    private func reconnectTunnel(to nextRelay: NextRelay, stopTunnelMonitor: Bool) async throws {
        guard state >= .starting && state <= .started else { return }

        // Cancel previous reconnection attempt
        reconnectTask?.cancel()

        reconnectTask = Task {
            try Task.checkCancellation()

            guard state == .starting || state == .started else { return }

            if stopTunnelMonitor {
                tunnelMonitor.stop()
            }

            do {
                let configuration = try makeConfiguration(nextRelay)

                setReasserting(true)

                try await adapter.update(tunnelConfiguration: configuration.wgTunnelConfig)

                guard state == .starting || state == .started else { return }

                selectorResult = configuration.selectorResult
                providerLogger.debug("Set tunnel relay to \(configuration.selectorResult.relay.hostname).")

                tunnelMonitor.start(probeAddress: configuration.selectorResult.endpoint.ipv4Gateway)
            } catch {
                providerLogger.error(error: error, message: "Failed to reconnect the tunnel.")

                setReasserting(false)
            }
        }

        try await reconnectTask?.value
    }

    private func setReasserting(_ isReasserting: Bool) {
        if state == .started {
            packetTunnelProvider?.reasserting = isReasserting
        }
    }

    // MARK: - Private: Connection monitoring

    private func onEstablishConnection() async {
        guard state < .stopping else { return }

        providerLogger.debug("Connection established.")

        if state == .starting {
            state = .started
        }

        setReasserting(false)
    }

    private func onHandleConnectionRecovery() async {
        guard state < .stopping else { return }

        let (value, isOverflow) = numberOfFailedAttempts.addingReportingOverflow(1)
        numberOfFailedAttempts = isOverflow ? 0 : value

        if numberOfFailedAttempts.isMultiple(of: 2) {
            // startDeviceCheck()
        }

        providerLogger.debug("Recover connection. Picking next relay...")

        try? await reconnectTunnel(to: .automatic, stopTunnelMonitor: false)
    }

    private func onNetworkReachibilityChange(_ isNetworkReachable: Bool) async {
        self.isNetworkReachable = isNetworkReachable
    }
}

// MARK: - TunnelMonitorDelegate

extension PacketTunnelActor: TunnelMonitorDelegate {
    nonisolated func tunnelMonitorDidDetermineConnectionEstablished(_ tunnelMonitor: TunnelMonitor) {
        Task {
            await onEstablishConnection()
        }
    }

    nonisolated func tunnelMonitorDelegateShouldHandleConnectionRecovery(_ tunnelMonitor: TunnelMonitor) {
        Task {
            await onHandleConnectionRecovery()
        }
    }

    nonisolated func tunnelMonitor(
        _ tunnelMonitor: TunnelMonitor,
        networkReachabilityStatusDidChange isNetworkReachable: Bool
    ) {
        Task {
            await onNetworkReachibilityChange(isNetworkReachable)
        }
    }
}
