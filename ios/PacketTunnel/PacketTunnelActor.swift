//
//  PacketTunnelActor.swift
//  PacketTunnel
//
//  Created by pronebird on 30/06/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadLogging
import MullvadTypes
import NetworkExtension
import PacketTunnelCore
import struct RelaySelector.RelaySelectorResult
import struct TunnelProviderMessaging.PacketTunnelOptions
import WireGuardKitTypes

actor PacketTunnelActor {
    @Published var state: State = .initial

    private var isNetworkReachable = true
    private var numberOfFailedAttempts: UInt = 0

    private let logger = Logger(label: "PacketTunnelActor")

    private let adapter: TunnelAdapterProtocol
    private var tunnelMonitor: TunnelMonitorProtocol
    private let relaySelector: RelaySelectorProtocol

    private var startTask: Task<Void, Error>?
    private var reconnectTask: Task<Void, Error>?
    private var monitoringTask: Task<Void, Never>?

    var selectorResult: RelaySelectorResult?

    init(adapter: TunnelAdapterProtocol, tunnelMonitor: TunnelMonitorProtocol, relaySelector: RelaySelectorProtocol) {
        self.adapter = adapter
        self.tunnelMonitor = tunnelMonitor
        self.relaySelector = relaySelector
    }

    func start(options: [String: NSObject]?) async throws {
        guard case .initial = state else { return }

        state = .starting

        let parsedOptions = parseStartOptions(options ?? [:])
        logger.debug("\(parsedOptions.logFormat())")

        startTask = Task {
            do {
                try await startTunnel(options: parsedOptions)
            } catch {
                try Task.checkCancellation()

                logger.error(error: error, message: "Failed to start the tunnel.")

                await setErrorState(with: error)
            }
        }

        monitoringTask = Task {
            for await event in monitorEventStream {
                await handleMonitorEvent(event)
            }
        }

        try await startTask?.value
    }

    func stop() async throws {
        guard state.canTransition(to: .stopping) else { return }

        state = .stopping

        tunnelMonitor.stop()

        startTask?.cancel()
        reconnectTask?.cancel()
        monitoringTask?.cancel()

        try? await startTask?.value
        try? await reconnectTask?.value

        defer { state = .stopped }
        try await adapter.stop()
    }

    func reconnect(to nextRelay: NextRelay) async throws {
        try await reconnectTunnel(to: nextRelay, stopTunnelMonitor: true)
    }

    // MARK: - Private

    private func setErrorState(with error: Error) async {
        let context = ErrorStateContext(previousState: state, error: error)

        guard state.canTransition(to: .error(context)) else { return }

        state = .error(context)

        try? await startEmptyTunnel()
    }

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
            logger.error(error: error, message: "Failed to decode relay selector result passed from the app.")
        }

        return parsedOptions
    }

    private func makeConfiguration(_ nextRelay: NextRelay) throws -> PacketTunnelConfiguration {
        let tunnelSettings = try SettingsManager.readSettings()
        let deviceState = try SettingsManager.readDeviceState()

        let selectorResult: RelaySelectorResult
        switch nextRelay {
        case .automatic:
            selectorResult = try relaySelector.selectRelay(
                with: tunnelSettings.relayConstraints,
                connectionAttemptFailureCount: numberOfFailedAttempts
            )
        case let .set(aSelectorResult):
            selectorResult = aSelectorResult
        }

        return PacketTunnelConfiguration(
            deviceState: deviceState,
            tunnelSettings: tunnelSettings,
            selectorResult: selectorResult
        )
    }

    private func startTunnel(options: StartOptions) async throws {
        let selectedRelay: NextRelay = options.selectorResult.map { .set($0) } ?? .automatic
        let configuration = try makeConfiguration(selectedRelay)

        try await adapter.start(configuration: configuration.wgTunnelConfig)
        selectorResult = configuration.selectorResult
    }

    private func startEmptyTunnel() async throws {
        let emptyTunnelConfiguration = TunnelConfiguration(
            name: nil,
            interface: InterfaceConfiguration(privateKey: PrivateKey()),
            peers: []
        )

        try await adapter.start(configuration: emptyTunnelConfiguration)
    }

    private func reconnectTunnel(to nextRelay: NextRelay, stopTunnelMonitor: Bool) async throws {
        guard state.isReconnecting || state.canTransition(to: .reconnecting) else { return }

        state = .reconnecting

        // Cancel previous reconnection attempt
        reconnectTask?.cancel()
        let oldReconnectTask = reconnectTask

        reconnectTask = Task {
            // Wait for previous task to complete
            try? await oldReconnectTask?.value
            try Task.checkCancellation()

            // Make sure we can still reconnect.
            guard case .reconnecting = state else { return }

            if stopTunnelMonitor {
                tunnelMonitor.stop()
            }

            do {
                let configuration = try makeConfiguration(nextRelay)

                try await adapter.update(configuration: configuration.wgTunnelConfig)

                try Task.checkCancellation()
                guard case .reconnecting = state else { return }

                selectorResult = configuration.selectorResult
                logger.debug("Set tunnel relay to \(configuration.selectorResult.relay.hostname).")

                tunnelMonitor.start(probeAddress: configuration.selectorResult.endpoint.ipv4Gateway)
            } catch {
                logger.error(error: error, message: "Failed to reconnect the tunnel.")
            }
        }
    }

    // MARK: - Private: Connection monitoring

    private var monitorEventStream: AsyncStream<TunnelMonitorEvent> {
        return AsyncStream { cont in
            tunnelMonitor.onEvent = { event in
                cont.yield(event)
            }
        }
    }

    private func onEstablishConnection() async {
        if state.canTransition(to: .started) {
            logger.debug("Connection established.")

            state = .started
        }
    }

    private func onHandleConnectionRecovery() async {
        guard state.isReconnecting || state.canTransition(to: .reconnecting) else { return }

        let (value, isOverflow) = numberOfFailedAttempts.addingReportingOverflow(1)
        numberOfFailedAttempts = isOverflow ? 0 : value

        if numberOfFailedAttempts.isMultiple(of: 2) {
            // TODO: startDeviceCheck()
        }

        logger.debug("Recover connection. Picking next relay...")

        try? await reconnectTunnel(to: .automatic, stopTunnelMonitor: false)
    }

    private func onNetworkReachibilityChange(_ isNetworkReachable: Bool) async {
        self.isNetworkReachable = isNetworkReachable
    }

    private func handleMonitorEvent(_ event: TunnelMonitorEvent) async {
        switch event {
        case .connectionEstablished:
            await onEstablishConnection()

        case .connectionLost:
            await onHandleConnectionRecovery()

        case let .networkReachabilityChanged(isNetworkReachable):
            await onNetworkReachibilityChange(isNetworkReachable)
        }
    }
}
