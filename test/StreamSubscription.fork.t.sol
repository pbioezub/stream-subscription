// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import {
    ISuperfluid,
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import { GDAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/GDAv1Forwarder.sol";

import { StreamSubscription } from "../src/StreamSubscription.sol";
import { StreamSubscriptionFactory } from "../src/StreamSubscriptionFactory.sol";

/// Fork tests against the real Superfluid deployments on Optimism.
/// Run with: OP_SEPOLIA_RPC_URL=... OP_MAINNET_RPC_URL=... forge test --match-contract Fork
contract StreamSubscriptionForkTest is Test {
    // from lib/protocol-monorepo/packages/metadata/networks.json
    ISuperfluid internal constant OP_MAINNET_HOST = ISuperfluid(0x567c4B141ED61923967cA25Ef4906C8781069a10);
    ISuperToken internal constant OP_MAINNET_ETHX = ISuperToken(0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d);
    ISuperfluid internal constant OP_SEPOLIA_HOST = ISuperfluid(0xd399e2Fb5f4cf3722a11F65b88FAB6B2B8621005);
    ISuperToken internal constant OP_SEPOLIA_ETHX = ISuperToken(0x0043d7c85C8b96a49A72A92C0B48CdC4720437d7);

    CFAv1Forwarder internal constant CFA_FORWARDER = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);
    GDAv1Forwarder internal constant GDA_FORWARDER = GDAv1Forwarder(0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08);

    int96 internal constant MIN_RATE = 1e9;

    /// OP Sepolia: registration is open, the whole flow works end-to-end with native ETHx:
    /// reserve -> subscribe -> revenue streamed to a pool member -> unsubscribe without jailing.
    function testForkOpSepoliaEndToEnd() public {
        string memory rpc = vm.envOr("OP_SEPOLIA_RPC_URL", string(""));
        vm.skip(bytes(rpc).length == 0);
        vm.createSelectFork(rpc);

        address creator = makeAddr("creator");
        address alice = makeAddr("alice");
        address collab = makeAddr("collab");
        _wrapEth(creator, 1 ether);
        _wrapEth(alice, 1 ether);

        StreamSubscriptionFactory factory = new StreamSubscriptionFactory(OP_SEPOLIA_HOST);
        vm.startPrank(creator);
        OP_SEPOLIA_ETHX.approve(address(factory), 0.1 ether);
        StreamSubscription sub = factory.create(OP_SEPOLIA_ETHX, MIN_RATE, 8000, 0.1 ether);
        address[] memory m = new address[](1);
        uint128[] memory u = new uint128[](1);
        (m[0], u[0]) = (collab, 1);
        sub.setMemberUnits(m, u);
        vm.stopPrank();
        assertTrue(OP_SEPOLIA_HOST.isApp(sub));

        ISuperfluidPool pool = sub.pool(); // cached: vm.prank applies to the next external call only
        vm.prank(collab);
        GDA_FORWARDER.connectPool(pool, "");

        vm.prank(alice);
        CFA_FORWARDER.setFlowrate(OP_SEPOLIA_ETHX, address(sub), MIN_RATE * 1000);
        assertTrue(sub.isSubscribed(alice));
        assertGt(sub.distributionFlowRate(), 0);

        vm.warp(block.timestamp + 1 days);
        assertApproxEqRel(OP_SEPOLIA_ETHX.balanceOf(collab), uint256(uint96(MIN_RATE * 1000)) * 1 days * 8 / 10, 1e14);

        vm.prank(alice);
        CFA_FORWARDER.setFlowrate(OP_SEPOLIA_ETHX, address(sub), 0);
        assertFalse(sub.isSubscribed(alice));
        assertFalse(OP_SEPOLIA_HOST.isAppJailed(sub));
    }

    function _wrapEth(address who, uint256 amount) internal {
        vm.deal(who, amount);
        vm.prank(who);
        (bool ok,) = address(OP_SEPOLIA_ETHX).call{ value: amount }(abi.encodeWithSignature("upgradeByETH()"));
        assertTrue(ok);
    }

    /// OP Mainnet: registration is permissioned, an unapproved factory can't register apps.
    function testForkOpMainnetRequiresWhitelisting() public {
        string memory rpc = vm.envOr("OP_MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpc).length == 0);
        vm.createSelectFork(rpc);

        (, bytes memory ret) =
            address(OP_MAINNET_HOST).staticcall(abi.encodeWithSignature("APP_WHITE_LISTING_ENABLED()"));
        assertTrue(abi.decode(ret, (bool)));
        StreamSubscriptionFactory factory = new StreamSubscriptionFactory(OP_MAINNET_HOST);
        vm.expectRevert(); // HOST_NO_APP_REGISTRATION_PERMISSION
        factory.create(OP_MAINNET_ETHX, MIN_RATE, 8000, 0);
    }
}
