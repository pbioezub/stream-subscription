// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import {
    ERC1820RegistryCompiled
} from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {
    SuperfluidFrameworkDeployer
} from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { StreamSubscription } from "../src/StreamSubscription.sol";
import { StreamSubscriptionFactory } from "../src/StreamSubscriptionFactory.sol";

contract StreamSubscriptionTest is Test {
    using SuperTokenV1Library for ISuperToken;

    // ~10 tokens / 30 days
    int96 internal constant MIN_RATE = int96(int256(uint256(10e18) / 30 days));
    uint256 internal constant POOL_SHARE_BPS = 8000; // 80% to the pool, 20% retained
    uint256 internal constant RESERVE = 10e18;

    SuperfluidFrameworkDeployer.Framework internal sf;
    ISuperToken internal token;
    ISuperToken internal otherToken;

    StreamSubscriptionFactory internal factory;
    StreamSubscription internal sub;
    ISuperfluidPool internal pool;

    address internal creator = makeAddr("creator");
    address internal collab1 = makeAddr("collab1");
    address internal collab2 = makeAddr("collab2");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.ADDRESS, ERC1820RegistryCompiled.BYTECODE);
        SuperfluidFrameworkDeployer deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();

        (, SuperToken st) = deployer.deployWrapperSuperToken("Fake USDC", "fUSDC", 18, type(uint256).max, address(0));
        token = ISuperToken(address(st));
        (, st) = deployer.deployWrapperSuperToken("Other", "OTH", 18, type(uint256).max, address(0));
        otherToken = ISuperToken(address(st));

        _fund(token, alice, 1000e18);
        _fund(token, bob, 1000e18);
        _fund(token, creator, 1000e18);

        factory = new StreamSubscriptionFactory(sf.host);
        vm.startPrank(creator);
        token.approve(address(factory), RESERVE);
        sub = factory.create(token, MIN_RATE, POOL_SHARE_BPS, RESERVE);
        vm.stopPrank();
        pool = sub.pool();
    }

    function _fund(ISuperToken t, address who, uint256 amount) internal {
        TestToken u = TestToken(t.getUnderlyingToken());
        vm.startPrank(who);
        u.mint(who, amount);
        u.approve(address(t), amount);
        t.upgrade(amount);
        vm.stopPrank();
    }

    /// @dev Single external call, exactly like a user opening a stream from a dApp.
    function _setFlow(ISuperToken t, address from, int96 rate) internal {
        vm.prank(from);
        sf.cfaV1Forwarder.setFlowrate(t, address(sub), rate);
    }

    function _setUnits(address a, uint128 ua, address b, uint128 ub) internal {
        address[] memory m = new address[](2);
        uint128[] memory u = new uint128[](2);
        (m[0], m[1], u[0], u[1]) = (a, b, ua, ub);
        vm.prank(creator);
        sub.setMemberUnits(m, u);
    }

    function _connect(address member) internal {
        vm.prank(member);
        sf.gdaV1Forwarder.connectPool(pool, "");
    }

    /// @dev What GDA actually streams for the current target (per-unit rate is rounded down).
    function _expectedDistribution() internal view returns (int96 actual) {
        (actual,) = token.estimateFlowDistributionActualFlowRate(address(sub), pool, sub.targetDistributionFlowRate());
    }

    function _assertHealthy() internal view {
        assertFalse(sf.host.isAppJailed(sub), "jailed");
        (int256 available,,,) = token.realtimeBalanceOfNow(address(sub));
        assertGe(available, 0, "app insolvent");
    }

    // ---------------------------------------------------------------------------------------------
    // SETUP / FACTORY

    function testSetup() public view {
        assertTrue(sf.host.isApp(sub));
        assertEq(pool.admin(), address(sub));
        assertEq(sub.owner(), creator);
        assertEq(sub.poolShareBps(), POOL_SHARE_BPS);
        assertEq(token.balanceOf(address(sub)), RESERVE);
        assertEq(factory.subscriptionsCount(), 1);
        assertEq(factory.subscriptionsOf(creator).length, 1);
    }

    function testConstructorValidation() public {
        vm.expectRevert(StreamSubscription.InvalidMinFlowRate.selector);
        factory.create(token, 0, POOL_SHARE_BPS, 0);
        vm.expectRevert(StreamSubscription.InvalidPoolShare.selector);
        factory.create(token, MIN_RATE, 10_001, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // SUBSCRIPTIONS

    function testSubscribeAndUnsubscribe() public {
        _setUnits(collab1, 1, collab2, 1);
        assertFalse(sub.isSubscribed(alice));

        _setFlow(token, alice, MIN_RATE);
        assertTrue(sub.isSubscribed(alice));
        assertEq(sub.totalInflowRate(), MIN_RATE);
        assertEq(sub.distributionFlowRate(), _expectedDistribution());
        assertGt(sub.distributionFlowRate(), 0);

        _setFlow(token, alice, 0);
        assertFalse(sub.isSubscribed(alice));
        assertEq(sub.distributionFlowRate(), 0);
        _assertHealthy();
    }

    function testSubscriberCount() public {
        _setFlow(token, alice, MIN_RATE);
        _setFlow(token, bob, MIN_RATE);
        assertEq(sub.subscriberCount(), 2);
        _setFlow(token, alice, MIN_RATE * 2); // update doesn't count
        assertEq(sub.subscriberCount(), 2);
        _setFlow(token, alice, 0);
        assertEq(sub.subscriberCount(), 1);
    }

    function testPause() public {
        _setFlow(token, alice, MIN_RATE);

        vm.prank(alice);
        vm.expectRevert(StreamSubscription.NotOwner.selector);
        sub.setPaused(true);

        vm.prank(creator);
        sub.setPaused(true);

        vm.expectRevert(); // SubscriptionsPaused
        _setFlow(token, bob, MIN_RATE);

        // existing subscribers aren't affected
        _setFlow(token, alice, MIN_RATE * 2);
        assertTrue(sub.isSubscribed(alice));
        _setFlow(token, alice, 0);
        _assertHealthy();

        vm.prank(creator);
        sub.setPaused(false);
        _setFlow(token, bob, MIN_RATE);
        assertTrue(sub.isSubscribed(bob));
    }

    /// Callbacks run with a 3M gas limit; the whole create/delete tx (incl. the callback) stays well below it.
    function testCallbackGas() public {
        _setUnits(collab1, 1, collab2, 1);
        vm.prank(alice);
        uint256 g = gasleft();
        sf.cfaV1Forwarder.setFlowrate(token, address(sub), MIN_RATE);
        uint256 createGas = g - gasleft();
        vm.prank(alice);
        g = gasleft();
        sf.cfaV1Forwarder.setFlowrate(token, address(sub), 0);
        uint256 deleteGas = g - gasleft();
        emit log_named_uint("create tx gas", createGas);
        emit log_named_uint("delete tx gas", deleteGas);
        assertLt(createGas, 3_000_000);
        assertLt(deleteGas, 3_000_000);
    }

    function testRejectsTooLowFlowRate() public {
        vm.expectRevert(); // FlowRateTooLow bubbles up through the host
        _setFlow(token, alice, MIN_RATE - 1);
        assertFalse(sub.isSubscribed(alice));
    }

    function testRejectsDowngradeBelowMin() public {
        _setUnits(collab1, 1, collab2, 1);
        _setFlow(token, alice, MIN_RATE * 2);
        vm.expectRevert();
        _setFlow(token, alice, MIN_RATE - 1);
        _setFlow(token, alice, MIN_RATE * 3);
        assertEq(sub.subscriberFlowRate(alice), MIN_RATE * 3);
        assertEq(sub.distributionFlowRate(), _expectedDistribution());
    }

    function testRejectsOtherToken() public {
        _fund(otherToken, alice, 100e18);
        vm.expectRevert(); // NotAcceptedSuperToken
        _setFlow(otherToken, alice, MIN_RATE);
    }

    // ---------------------------------------------------------------------------------------------
    // RESERVE

    function testRejectsWhenReserveMissing() public {
        vm.prank(creator);
        StreamSubscription empty = factory.create(token, MIN_RATE, POOL_SHARE_BPS, 0);
        address[] memory m = new address[](1);
        uint128[] memory u = new uint128[](1);
        (m[0], u[0]) = (collab1, 1);
        vm.prank(creator);
        empty.setMemberUnits(m, u);
        uint256 shortfall = empty.bufferShortfall(MIN_RATE);
        assertGt(shortfall, 0);

        vm.prank(alice);
        vm.expectRevert(); // InsufficientReserve
        sf.cfaV1Forwarder.setFlowrate(token, address(empty), MIN_RATE);

        // anyone can top up the reserve, then the subscription goes through
        vm.prank(creator);
        token.transfer(address(empty), shortfall);
        assertEq(empty.bufferShortfall(MIN_RATE), 0);
        vm.prank(alice);
        sf.cfaV1Forwarder.setFlowrate(token, address(empty), MIN_RATE);
        assertTrue(empty.isSubscribed(alice));
    }

    function testZeroPoolShareNeedsNoReserve() public {
        vm.prank(creator);
        StreamSubscription noSplit = factory.create(token, MIN_RATE, 0, 0);
        vm.prank(alice);
        sf.cfaV1Forwarder.setFlowrate(token, address(noSplit), MIN_RATE);
        assertTrue(noSplit.isSubscribed(alice));
        assertEq(noSplit.distributionFlowRate(), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // REVENUE SHARING

    function testRevenueSplit() public {
        _setUnits(collab1, 3, collab2, 1); // 75% / 25% of the pool share
        _connect(collab1);
        _connect(collab2);

        _setFlow(token, alice, MIN_RATE * 10);
        uint256 subBefore = token.balanceOf(address(sub));

        vm.warp(block.timestamp + 30 days);

        uint256 inflow = uint256(uint96(MIN_RATE * 10)) * 30 days;
        uint256 toPool = inflow * POOL_SHARE_BPS / 10_000;
        uint256 c1Got = token.balanceOf(collab1);
        uint256 c2Got = token.balanceOf(collab2);
        uint256 retained = token.balanceOf(address(sub)) - subBefore;

        // GDA rounds the per-unit rate down; remainders stay with the app (pool admin)
        assertApproxEqRel(c1Got, toPool * 3 / 4, 1e12);
        assertApproxEqRel(c2Got, toPool / 4, 1e12);
        assertApproxEqRel(retained, inflow - toPool, 1e12);
        assertEq(c1Got + c2Got + retained, inflow, "no value created or lost");
        _assertHealthy();
    }

    function testNoUnitsFundsStayInApp() public {
        _setFlow(token, alice, MIN_RATE);
        uint256 before = token.balanceOf(address(sub));
        vm.warp(block.timestamp + 10 days);
        // no members: the GDA adjustment flow returns everything to the app (pool admin)
        assertEq(token.balanceOf(address(sub)) - before, uint256(uint96(MIN_RATE)) * 10 days);
    }

    function testAddingUnitsStartsDistribution() public {
        _setFlow(token, alice, MIN_RATE);
        assertEq(sub.distributionFlowRate(), 0); // no members yet
        _setUnits(collab1, 1, collab2, 1);
        assertEq(sub.distributionFlowRate(), _expectedDistribution());
        assertGt(sub.distributionFlowRate(), 0);

        _setUnits(collab1, 0, collab2, 0); // removing everyone stops it again
        assertEq(sub.distributionFlowRate(), 0);
        _setFlow(token, alice, 0);
        _assertHealthy();
    }

    function testOwnerWithdrawsRetainedRevenue() public {
        _setUnits(collab1, 1, collab2, 1);
        _setFlow(token, alice, MIN_RATE);
        _setFlow(token, bob, MIN_RATE * 2);
        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        vm.expectRevert(StreamSubscription.NotOwner.selector);
        sub.withdraw(alice, type(uint256).max);

        uint256 w = sub.withdrawable();
        uint256 before = token.balanceOf(creator);
        vm.prank(creator);
        sub.withdraw(creator, type(uint256).max);
        assertEq(token.balanceOf(creator) - before, w);
        assertEq(sub.withdrawable(), 0);

        // even fully drained, leaving subscribers never jails the app
        _setFlow(token, alice, 0);
        _setFlow(token, bob, 0);
        _assertHealthy();
    }

    function testOnlyOwnerSetsUnits() public {
        address[] memory m = new address[](1);
        uint128[] memory u = new uint128[](1);
        vm.prank(alice);
        vm.expectRevert(StreamSubscription.NotOwner.selector);
        sub.setMemberUnits(m, u);
        vm.prank(creator);
        vm.expectRevert(StreamSubscription.LengthMismatch.selector);
        sub.setMemberUnits(m, new uint128[](0));
    }

    // ---------------------------------------------------------------------------------------------
    // JAILING / SOLVENCY

    /// Liquidation of an insolvent subscriber must not jail the app.
    function testLiquidationDoesNotJail() public {
        address poor = makeAddr("poor");
        _fund(token, poor, 5e18);
        _setFlow(token, poor, MIN_RATE);

        vm.warp(block.timestamp + 30 days); // poor's balance is exhausted
        (int256 avb,,,) = token.realtimeBalanceOfNow(poor);
        assertLt(avb, 0);

        vm.prank(bob); // anyone may liquidate a critical sender
        sf.host
            .callAgreement(
                sf.cfa, abi.encodeCall(sf.cfa.deleteFlow, (token, poor, address(sub), new bytes(0))), new bytes(0)
            );
        assertFalse(sub.isSubscribed(poor));
        assertEq(sub.subscriberCount(), 0);
        assertEq(sub.distributionFlowRate(), 0);
        _assertHealthy();
    }

    /// Worst case for the termination callback: governance raises the minimum deposit so that even
    /// a lower distribution needs more buffer than the app has. The app halts instead of being jailed.
    function testDeleteCallbackHaltsInsteadOfJailing() public {
        _setUnits(collab1, 1, collab2, 1);
        _setFlow(token, alice, MIN_RATE);
        _setFlow(token, bob, MIN_RATE);
        vm.prank(creator);
        sub.withdraw(creator, type(uint256).max); // no spare balance at all

        vm.prank(sf.governance.owner());
        sf.governance.setSuperTokenMinimumDeposit(sf.host, token, 1_000_000e18);

        vm.expectEmit(false, false, false, false, address(sub));
        emit StreamSubscription.DistributionHalted(0);
        _setFlow(token, alice, 0);

        assertEq(sub.distributionFlowRate(), 0);
        assertTrue(sub.isSubscribed(bob));
        _assertHealthy();

        // sync() reverts while unaffordable...
        vm.expectRevert();
        sub.sync();
        // ...and resumes once it is affordable again
        vm.prank(sf.governance.owner());
        sf.governance.setSuperTokenMinimumDeposit(sf.host, token, 0);
        sub.sync();
        assertEq(sub.distributionFlowRate(), _expectedDistribution());
        assertGt(sub.distributionFlowRate(), 0);
    }

    /// Many subscribers join, change and leave in random order: the app is never jailed or insolvent
    /// and the distribution always matches the target after each change.
    function testFuzzManySubscribers(uint256 seed) public {
        address[5] memory subs;
        for (uint256 i = 0; i < subs.length; ++i) {
            subs[i] = makeAddr(string(abi.encode("s", i)));
            _fund(token, subs[i], 100_000e18);
        }
        _setUnits(collab1, 2, collab2, 5);

        for (uint256 step = 0; step < 15; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            address s = subs[seed % subs.length];
            int96 rate = (seed >> 8) % 3 == 0 ? int96(0) : MIN_RATE * int96(int256(1 + (seed >> 16) % 50));
            if (rate == 0 && sub.subscriberFlowRate(s) == 0) continue;
            _setFlow(token, s, rate);
            vm.warp(block.timestamp + (seed >> 32) % 1 days);

            assertEq(sub.distributionFlowRate(), _expectedDistribution());
            assertLe(sub.distributionFlowRate(), sub.totalInflowRate());
            _assertHealthy();
        }
        for (uint256 i = 0; i < subs.length; ++i) {
            if (sub.subscriberFlowRate(subs[i]) > 0) _setFlow(token, subs[i], 0);
        }
        assertEq(sub.distributionFlowRate(), 0);
        _assertHealthy();
    }

    // ---------------------------------------------------------------------------------------------
    // OWNERSHIP

    function testTwoStepOwnership() public {
        vm.prank(creator);
        sub.transferOwnership(alice);
        assertEq(sub.owner(), creator);

        vm.prank(bob);
        vm.expectRevert(StreamSubscription.NotPendingOwner.selector);
        sub.acceptOwnership();

        vm.prank(alice);
        sub.acceptOwnership();
        assertEq(sub.owner(), alice);
        assertEq(sub.pendingOwner(), address(0));
    }
}
