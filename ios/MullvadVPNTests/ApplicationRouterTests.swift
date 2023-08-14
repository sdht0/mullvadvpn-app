//
//  ApplicationRouterTests.swift
//  MullvadVPNTests
//
//  Created by pronebird on 14/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
@testable import MullvadVPN
import XCTest

final class ApplicationRouterTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPresentRoute() throws {
        let delegate = RouterBlockDelegate<TestRoute>()

        delegate.handleRoute = { route, animated, completion in
            completion(Coordinator())
        }

        delegate.shouldPresent = { route in
            return true
        }

        let router = ApplicationRouter<TestRoute>(delegate)

        router.present(.one)

        XCTAssertTrue(router.isPresenting(route: .one))
    }

    func testShouldDropRoutePresentation() throws {
        let delegate = RouterBlockDelegate<TestRoute>()

        delegate.handleRoute = { route, animated, completion in
            completion(Coordinator())
        }

        delegate.shouldPresent = { route in
            return false
        }

        let router = ApplicationRouter<TestRoute>(delegate)

        router.present(.one)

        XCTAssertFalse(router.isPresenting(route: .one))
    }

}

enum TestRoute: AppRouteProtocol {

    typealias RouteGroupType = TestRouteGroup

    case one, two

    var isExclusive: Bool {
        return true
    }

    var supportsSubNavigation: Bool {
        return false
    }

    var routeGroup: TestRouteGroup {
        return TestRouteGroup()
    }
}

struct TestRouteGroup: AppRouteGroupProtocol {
    static func < (lhs: TestRouteGroup, rhs: TestRouteGroup) -> Bool {
        return false
    }

    var isModal: Bool {
        return false
    }
}

class RouterBlockDelegate<RouteType: AppRouteProtocol>: ApplicationRouterDelegate {

    var handleRoute: ((RouteType, Bool, (Coordinator) -> Void) -> Void)?
    var handleDismiss: ((RouteDismissalContext<RouteType>, () -> Void) -> Void)?
    var shouldPresent: ((RouteType) -> Bool)?
    var shouldDismiss: ((RouteDismissalContext<RouteType>) -> Bool)?
    var handleSubnavigation: ((RouteSubnavigationContext<RouteType>, () -> Void) -> Void)?

    func applicationRouter(_ router: ApplicationRouter<RouteType>, route: RouteType, animated: Bool, completion: @escaping (Coordinator) -> Void) {
        handleRoute?(route, animated, completion) ?? completion(Coordinator())
    }

    func applicationRouter(_ router: ApplicationRouter<RouteType>, dismissWithContext context: RouteDismissalContext<RouteType>, completion: @escaping () -> Void) {
        handleDismiss?(context, completion) ?? completion()
    }

    func applicationRouter(_ router: ApplicationRouter<RouteType>, shouldPresent route: RouteType) -> Bool {
        return shouldPresent?(route) ?? true
    }

    func applicationRouter(_ router: ApplicationRouter<RouteType>, shouldDismissWithContext context: RouteDismissalContext<RouteType>) -> Bool {
        return shouldDismiss?(context) ?? true
    }

    func applicationRouter(_ router: ApplicationRouter<RouteType>, handleSubNavigationWithContext context: RouteSubnavigationContext<RouteType>, completion: @escaping () -> Void) {
        handleSubnavigation?(context, completion) ?? completion()
    }


}
