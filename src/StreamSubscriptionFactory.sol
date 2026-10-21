// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    ISuperfluid,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { StreamSubscription } from "./StreamSubscription.sol";

/// @notice Deploys and registers StreamSubscription apps.
/// @dev Where app registration is permissioned (e.g. OP Mainnet) this factory has to be allowlisted by Superfluid.
contract StreamSubscriptionFactory {
    ISuperfluid public immutable host;

    StreamSubscription[] public subscriptions;
    mapping(address owner => StreamSubscription[]) internal _byOwner;

    event SubscriptionCreated(
        address indexed subscription,
        address indexed owner,
        ISuperToken indexed token,
        address pool,
        int96 minFlowRate,
        uint256 poolShareBps
    );

    error ReserveTransferFailed();

    constructor(ISuperfluid host_) {
        host = host_;
    }

    /// @param initialReserve pulled from msg.sender (needs approval), pays for the GDA buffer
    function create(ISuperToken token, int96 minFlowRate, uint256 poolShareBps, uint256 initialReserve)
        external
        returns (StreamSubscription subscription)
    {
        subscription = new StreamSubscription(host, token, minFlowRate, poolShareBps, msg.sender);
        host.registerApp(subscription, subscription.getConfigWord(true, true, true));

        if (initialReserve > 0 && !token.transferFrom(msg.sender, address(subscription), initialReserve)) {
            revert ReserveTransferFailed();
        }

        subscriptions.push(subscription);
        _byOwner[msg.sender].push(subscription);
        emit SubscriptionCreated(
            address(subscription), msg.sender, token, address(subscription.pool()), minFlowRate, poolShareBps
        );
    }

    function subscriptionsCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function subscriptionsOf(address owner) external view returns (StreamSubscription[] memory) {
        return _byOwner[owner];
    }
}
