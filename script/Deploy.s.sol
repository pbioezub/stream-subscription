// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import {
    ISuperfluid,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { StreamSubscription } from "../src/StreamSubscription.sol";
import { StreamSubscriptionFactory } from "../src/StreamSubscriptionFactory.sol";

// forge script script/Deploy.s.sol --rpc-url optimism_sepolia --account deployer --broadcast --verify
// optional env: FACTORY, TOKEN, MIN_FLOW_RATE, POOL_SHARE_BPS (default 8000), RESERVE
contract Deploy is Script {
    function run() external {
        ISuperfluid host = _host();

        vm.startBroadcast();

        StreamSubscriptionFactory factory;
        address existing = vm.envOr("FACTORY", address(0));
        if (existing == address(0)) {
            factory = new StreamSubscriptionFactory(host);
            console.log("Factory deployed:", address(factory));
        } else {
            factory = StreamSubscriptionFactory(existing);
            console.log("Using factory:", existing);
        }

        address token = vm.envOr("TOKEN", address(0));
        if (token != address(0)) {
            int96 minFlowRate = int96(int256(vm.envUint("MIN_FLOW_RATE")));
            uint256 poolShareBps = vm.envOr("POOL_SHARE_BPS", uint256(8000));
            uint256 reserve = vm.envOr("RESERVE", uint256(0));
            if (reserve > 0) ISuperToken(token).approve(address(factory), reserve);
            StreamSubscription sub = factory.create(ISuperToken(token), minFlowRate, poolShareBps, reserve);
            console.log("Subscription deployed:", address(sub));
            console.log("Revenue pool:", address(sub.pool()));
        }

        vm.stopBroadcast();
    }

    // from packages/metadata/networks.json
    function _host() internal view returns (ISuperfluid) {
        if (block.chainid == 10) return ISuperfluid(0x567c4B141ED61923967cA25Ef4906C8781069a10);
        if (block.chainid == 11155420) return ISuperfluid(0xd399e2Fb5f4cf3722a11F65b88FAB6B2B8621005);
        revert("unsupported chain");
    }
}
