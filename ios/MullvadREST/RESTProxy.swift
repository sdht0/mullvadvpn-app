//
//  RESTProxy.swift
//  MullvadREST
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes
import Operations

extension REST {
    public class Proxy<ConfigurationType: ProxyConfiguration> {
        public typealias CompletionHandler<Success> = (Result<Success, Swift.Error>) -> Void

        /// An alias for a concrete ProxyTaskFactory implementation type.
        typealias ProxyTaskFactory<Success> = ProxyTaskFactoryImp<ConfigurationType, Success>

        /// Synchronization queue used by network operations.
        let dispatchQueue: DispatchQueue

        /// Operation queue used for running network operations.
        let operationQueue = AsyncOperationQueue()

        /// Proxy configuration.
        let configuration: ConfigurationType

        /// URL request factory.
        let requestFactory: REST.RequestFactory

        /// URL response decoder.
        let responseDecoder: JSONDecoder

        init(
            name: String,
            configuration: ConfigurationType,
            requestFactory: REST.RequestFactory,
            responseDecoder: JSONDecoder
        ) {
            dispatchQueue = DispatchQueue(label: "REST.\(name).dispatchQueue")
            operationQueue.name = "REST.\(name).operationQueue"

            self.configuration = configuration
            self.requestFactory = requestFactory
            self.responseDecoder = responseDecoder
        }

        /// Returns task factory configured with the given request and response handlers.
        func makeTaskFactory<Success>(
            name: String,
            retryStrategy: REST.RetryStrategy,
            requestHandler: RESTRequestHandler,
            responseHandler: some RESTResponseHandler<Success>
        ) -> ProxyTaskFactory<Success> {
            return ProxyTaskFactory(
                dispatchQueue: dispatchQueue,
                operationQueue: operationQueue,
                configuration: configuration,
                taskDescription: ProxyTaskDescription(
                    name: name,
                    retryStrategy: retryStrategy,
                    requestHandler: requestHandler,
                    responseHandler: responseHandler
                )
            )
        }
    }

    /// Struct holding dependencies necessary to instantiate network operation.
    struct ProxyTaskDescription<Success> {
        let name: String
        let retryStrategy: REST.RetryStrategy
        let requestHandler: RESTRequestHandler
        let responseHandler: any RESTResponseHandler<Success>
    }

    /**
     Factory type that creates and schedules `NetworkOperation` for execution and provides facilities to receive
     the response either via swift concurrency or traditional callback.
     */
    struct ProxyTaskFactoryImp<ConfigurationType: ProxyConfiguration, Success> {
        private let dispatchQueue: DispatchQueue
        private let operationQueue: OperationQueue
        private let configuration: ConfigurationType
        private let taskDescription: ProxyTaskDescription<Success>

        fileprivate init(
            dispatchQueue: DispatchQueue,
            operationQueue: OperationQueue,
            configuration: ConfigurationType,
            taskDescription: ProxyTaskDescription<Success>
        ) {
            self.dispatchQueue = dispatchQueue
            self.operationQueue = operationQueue
            self.configuration = configuration
            self.taskDescription = taskDescription
        }

        /// Create and schedule network operation for exection.
        func execute() async throws -> Success {
            let operation = makeOperation()

            return try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { continuation in
                    operation.completionHandler = { result in
                        continuation.resume(with: result)
                    }
                    operationQueue.addOperation(operation)
                }
            } onCancel: {
                operation.cancel()
            }
        }

        /// Create and schedule network operation for exection.
        func execute(completionHandler: @escaping (Result<Success, Swift.Error>) -> Void) -> Cancellable {
            let operation = makeOperation(completionHandler: completionHandler)

            operationQueue.addOperation(operation)

            return operation
        }

        private func makeOperation(completionHandler: ((Result<Success, Swift.Error>) -> Void)? = nil)
            -> NetworkOperation<Success>
        {
            return NetworkOperation(
                name: getTaskIdentifier(name: taskDescription.name),
                dispatchQueue: dispatchQueue,
                configuration: configuration,
                retryStrategy: taskDescription.retryStrategy,
                requestHandler: taskDescription.requestHandler,
                responseHandler: taskDescription.responseHandler,
                completionHandler: completionHandler
            )
        }
    }

    public class ProxyConfiguration {
        public let transportProvider: () -> RESTTransportProvider?
        public let addressCacheStore: AddressCache

        public init(
            transportProvider: @escaping () -> RESTTransportProvider?,
            addressCacheStore: AddressCache
        ) {
            self.transportProvider = transportProvider
            self.addressCacheStore = addressCacheStore
        }
    }

    public class AuthProxyConfiguration: ProxyConfiguration {
        public let accessTokenManager: AccessTokenManager

        public init(
            proxyConfiguration: ProxyConfiguration,
            accessTokenManager: AccessTokenManager
        ) {
            self.accessTokenManager = accessTokenManager

            super.init(
                transportProvider: proxyConfiguration.transportProvider,
                addressCacheStore: proxyConfiguration.addressCacheStore
            )
        }
    }
}
