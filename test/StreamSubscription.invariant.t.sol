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
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { StreamSubscription } from "../src/StreamSubscription.sol";
import { StreamSubscriptionFactory } from "../src/StreamSubscriptionFactory.sol";

contract Handler is Test {
    using SuperTokenV1Library for ISuperToken;

    SuperfluidFrameworkDeployer.Framework internal sf;
    ISuperToken internal token;
    StreamSubscription internal sub;
    address internal owner;
    int96 internal minRate;

    address[] public actors;
    address[] public members;

    constructor(
        SuperfluidFrameworkDeployer.Framework memory sf_,
        ISuperToken token_,
        StreamSubscription sub_,
        address owner_
    ) {
        sf = sf_;
        token = token_;
        sub = sub_;
        owner = owner_;
        minRate = sub_.minFlowRate();
        for (uint256 i = 0; i < 4; ++i) {
            address a = makeAddr(string(abi.encode("actor", i)));
            actors.push(a);
            _fund(a, 1e24);
            members.push(makeAddr(string(abi.encode("member", i))));
        }
        _fund(owner, 1e24);
    }

    function _fund(address who, uint256 amount) internal {
        TestToken u = TestToken(token.getUnderlyingToken());
        vm.startPrank(who);
        u.mint(who, amount);
        u.approve(address(token), amount);
        token.upgrade(amount);
        vm.stopPrank();
    }

    function setFlow(uint256 actorSeed, uint256 rateSeed) external {
        address a = actors[actorSeed % actors.length];
        int96 rate = minRate * int96(int256(bound(rateSeed, 1, 100)));
        int96 current = token.getCFAFlowRate(a, address(sub));
        uint256 shortfall = sub.bufferShortfall(rate - current);
        if (shortfall > 0) {
            vm.prank(owner);
            token.transfer(address(sub), shortfall);
        }
        vm.prank(a);
        sf.cfaV1Forwarder.setFlowrate(token, address(sub), rate);
    }

    function closeFlow(uint256 actorSeed) external {
        address a = actors[actorSeed % actors.length];
        if (token.getCFAFlowRate(a, address(sub)) == 0) return;
        vm.prank(a);
        sf.cfaV1Forwarder.setFlowrate(token, address(sub), 0);
    }

    function setUnits(uint256 memberSeed, uint128 units) external {
        address[] memory m = new address[](1);
        uint128[] memory u = new uint128[](1);
        (m[0], u[0]) = (members[memberSeed % members.length], uint128(bound(units, 0, 1000)));
        // adding units can start the distribution, which needs a buffer
        uint256 shortfall = sub.bufferShortfall(0);
        if (shortfall > 0) {
            vm.prank(owner);
            token.transfer(address(sub), shortfall);
        }
        vm.prank(owner);
        sub.setMemberUnits(m, u);
    }

    function withdraw(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 0, sub.withdrawable());
        vm.prank(owner);
        sub.withdraw(owner, amount);
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 3 days));
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract StreamSubscriptionInvariantTest is Test {
    using SuperTokenV1Library for ISuperToken;

    SuperfluidFrameworkDeployer.Framework internal sf;
    ISuperToken internal token;
    StreamSubscription internal sub;
    Handler internal handler;

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.ADDRESS, ERC1820RegistryCompiled.BYTECODE);
        SuperfluidFrameworkDeployer deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (, SuperToken st) = deployer.deployWrapperSuperToken("Fake USDC", "fUSDC", 18, type(uint256).max, address(0));
        token = ISuperToken(address(st));

        address owner = makeAddr("owner");
        StreamSubscriptionFactory factory = new StreamSubscriptionFactory(sf.host);
        vm.prank(owner);
        sub = factory.create(token, int96(int256(uint256(10e18) / 30 days)), 8000, 0);

        handler = new Handler(sf, token, sub, owner);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_neverJailed() public view {
        assertFalse(sf.host.isAppJailed(sub));
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_solvent() public view {
        (int256 available,,,) = token.realtimeBalanceOfNow(address(sub));
        assertGe(available, 0);
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_distributionWithinShare() public view {
        assertLe(sub.distributionFlowRate(), sub.targetDistributionFlowRate());
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_subscriberCountMatchesFlows() public view {
        uint256 open;
        for (uint256 i = 0; i < handler.actorCount(); ++i) {
            if (token.getCFAFlowRate(handler.actors(i), address(sub)) > 0) ++open;
        }
        assertEq(sub.subscriberCount(), open);
    }
}
