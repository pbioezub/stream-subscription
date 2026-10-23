// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    ISuperfluid,
    ISuperToken,
    ISuperfluidPool,
    PoolConfig
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { CFASuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFASuperAppBase.sol";

/// @title StreamSubscription
/// @notice Subscribers stream `token` to the app and count as subscribed while their flow rate is >= `minFlowRate`.
///         `poolShareBps` of the total inflow is streamed on to a GDA pool, the rest stays in the app for the owner.
/// @dev GDA doesn't use app credit, so the distribution buffer comes from the app's own balance (see `bufferShortfall`).
///      The delete callback must not revert - if the new buffer can't be paid there, the distribution is halted
///      and can be resumed with `sync()`.
contract StreamSubscription is CFASuperAppBase {
    using SuperTokenV1Library for ISuperToken;

    uint256 public constant BPS = 10_000;

    ISuperToken public immutable token;
    ISuperfluidPool public immutable pool;
    int96 public immutable minFlowRate;
    uint256 public immutable poolShareBps;

    address public owner;
    address public pendingOwner;

    /// @notice Number of open incoming streams.
    uint256 public subscriberCount;
    /// @notice When true, new streams are rejected. Existing ones keep working and can still be updated or closed.
    bool public paused;

    /// @notice Start of the current subscription, 0 if not subscribed.
    mapping(address subscriber => uint256) public subscribedSince;
    // streamed up to the last flow update, see `totalStreamed`
    mapping(address subscriber => uint256) internal _streamed;

    event Subscribed(address indexed subscriber, int96 flowRate);
    event SubscriptionUpdated(address indexed subscriber, int96 flowRate, int96 previousFlowRate);
    event Unsubscribed(address indexed subscriber, int96 previousFlowRate);
    event DistributionUpdated(int96 requestedFlowRate, int96 actualFlowRate);
    event DistributionHalted(int96 targetFlowRate);
    event MemberUnitsUpdated(address indexed member, uint128 units);
    event Withdrawn(address indexed to, uint256 amount);
    event PausedSet(bool paused);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error FlowRateTooLow(int96 flowRate, int96 minFlowRate);
    error InsufficientReserve(uint256 shortfall);
    error InvalidMinFlowRate();
    error InvalidPoolShare();
    error LengthMismatch();
    error ZeroAddress();
    error NotOwner();
    error NotPendingOwner();
    error TransferFailed();
    error SubscriptionsPaused();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(ISuperfluid host_, ISuperToken token_, int96 minFlowRate_, uint256 poolShareBps_, address owner_)
        CFASuperAppBase(host_)
    {
        if (address(token_) == address(0) || owner_ == address(0)) revert ZeroAddress();
        if (minFlowRate_ <= 0) revert InvalidMinFlowRate();
        if (poolShareBps_ > BPS) revert InvalidPoolShare();
        token = token_;
        minFlowRate = minFlowRate_;
        poolShareBps = poolShareBps_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);

        // app is the pool admin, so units go through the owner and unassigned flow comes back here
        pool = token_.createPool(
            address(this), PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: false })
        );

        // where registration is permissioned (e.g. OP Mainnet), tx.origin has to be an allowlisted deployer
        selfRegister(true, true, true);
    }

    // --- views ---

    function isSubscribed(address subscriber) external view returns (bool) {
        return token.getCFAFlowRate(subscriber, address(this)) >= minFlowRate;
    }

    function subscriberFlowRate(address subscriber) external view returns (int96) {
        return token.getCFAFlowRate(subscriber, address(this));
    }

    /// @notice Everything `subscriber` has streamed to the app so far, over all of their subscriptions.
    function totalStreamed(address subscriber) external view returns (uint256) {
        (uint256 lastUpdated, int96 rate,,) = token.getCFAFlowInfo(subscriber, address(this));
        return _streamed[subscriber] + _streamedSince(rate, lastUpdated);
    }

    function totalInflowRate() public view returns (int96) {
        int96 r = token.getCFANetFlowRate(address(this));
        return r > 0 ? r : int96(0);
    }

    function targetDistributionFlowRate() public view returns (int96) {
        return _poolShare(totalInflowRate());
    }

    function distributionFlowRate() external view returns (int96) {
        return token.getGDAFlowRate(address(this), pool);
    }

    function withdrawable() public view returns (uint256) {
        (int256 available,,,) = token.realtimeBalanceOfNow(address(this));
        return available > 0 ? uint256(available) : 0;
    }

    /// @notice Tokens missing from the reserve to accept `additionalFlowRate` more inflow (0 = ok).
    function bufferShortfall(int96 additionalFlowRate) external view returns (uint256) {
        int96 target = _poolShare(totalInflowRate() + additionalFlowRate);
        (int256 available,,,) = token.realtimeBalanceOfNow(address(this));
        int256 after_ = _availableAfter(target, available);
        return after_ >= 0 ? 0 : uint256(-after_);
    }

    function isAcceptedSuperToken(ISuperToken superToken) public view override returns (bool) {
        return address(superToken) == address(token);
    }

    // --- permissionless ---

    /// @notice Re-align the distribution with the inflow, e.g. after a halt or a reserve top-up.
    function sync() external {
        _sync();
    }

    // --- owner ---

    function setMemberUnits(address[] calldata members, uint128[] calldata units) external onlyOwner {
        if (members.length != units.length) revert LengthMismatch();
        for (uint256 i = 0; i < members.length; ++i) {
            pool.updateMemberUnits(members[i], units[i]);
            emit MemberUnitsUpdated(members[i], units[i]);
        }
        // nothing is distributed to a pool without units, so (re)start it here
        _sync();
    }

    /// @dev amount = type(uint256).max withdraws everything available
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == type(uint256).max) amount = withdrawable();
        if (!token.transfer(to, amount)) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    // address(0) cancels a pending transfer
    // forge-lint: disable-next-line(missing-zero-check)
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // --- super app callbacks ---

    function onFlowCreated(ISuperToken, address sender, int96 flowRate, bytes calldata ctx)
        internal
        override
        returns (bytes memory)
    {
        if (paused) revert SubscriptionsPaused();
        if (flowRate < minFlowRate) revert FlowRateTooLow(flowRate, minFlowRate);
        ++subscriberCount;
        subscribedSince[sender] = block.timestamp;
        emit Subscribed(sender, flowRate);
        return _syncDistribution(ctx, false);
    }

    function onFlowUpdated(
        ISuperToken,
        address sender,
        int96 flowRate,
        int96 previousFlowRate,
        uint256 lastUpdated,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        if (flowRate < minFlowRate) revert FlowRateTooLow(flowRate, minFlowRate);
        _streamed[sender] += _streamedSince(previousFlowRate, lastUpdated);
        emit SubscriptionUpdated(sender, flowRate, previousFlowRate);
        return _syncDistribution(ctx, false);
    }

    // must not revert, otherwise the app gets jailed
    function onInFlowDeleted(
        ISuperToken,
        address sender,
        int96 previousFlowRate,
        uint256 lastUpdated,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        // guarded: an underflow here would revert and jail the app
        if (subscriberCount > 0) --subscriberCount;
        delete subscribedSince[sender];
        _streamed[sender] += _streamedSince(previousFlowRate, lastUpdated);
        emit Unsubscribed(sender, previousFlowRate);
        return _syncDistribution(ctx, true);
    }

    // --- internal ---

    function _poolShare(int96 inflow) internal view returns (int96) {
        if (inflow <= 0) return 0;
        return int96(int256(uint256(uint96(inflow)) * poolShareBps / BPS));
    }

    // can't revert: rate fits in 96 bits and the elapsed time in far less than 160
    function _streamedSince(int96 rate, uint256 lastUpdated) internal view returns (uint256) {
        if (rate <= 0 || lastUpdated >= block.timestamp) return 0;
        return uint256(uint96(rate)) * (block.timestamp - lastUpdated);
    }

    // CFA deposit formula is used as an upper bound for the GDA buffer (same params, CFA also rounds up)
    function _availableAfter(int96 target, int256 available) internal view returns (int256) {
        (,, uint256 currentBuffer) = token.getGDAFlowInfo(address(this), pool);
        uint256 newBuffer = target > 0 ? token.getBufferAmountByFlowRate(target) : 0;
        return available + int256(currentBuffer) - int256(newBuffer);
    }

    function _sync() internal {
        int96 target = targetDistributionFlowRate();
        (int96 expected,) = token.estimateFlowDistributionActualFlowRate(address(this), pool, target);
        if (expected == token.getGDAFlowRate(address(this), pool)) return;
        token.distributeFlow(address(this), pool, target);
        emit DistributionUpdated(target, token.getGDAFlowRate(address(this), pool));
    }

    function _syncDistribution(bytes calldata ctx, bool mustNotRevert) internal returns (bytes memory newCtx) {
        int96 target = targetDistributionFlowRate();
        int96 current = token.getGDAFlowRate(address(this), pool);
        (int96 expected,) = token.estimateFlowDistributionActualFlowRate(address(this), pool, target);
        if (expected == current) return ctx;

        if (target > 0) {
            (int256 available,,,) = token.realtimeBalanceOfNow(address(this));
            int256 after_ = _availableAfter(target, available);
            if (after_ < 0) {
                if (!mustNotRevert) revert InsufficientReserve(uint256(-after_));
                emit DistributionHalted(target);
                target = 0;
            }
        }

        newCtx = token.distributeFlowWithCtx(address(this), pool, target, ctx);
        emit DistributionUpdated(target, token.getGDAFlowRate(address(this), pool));
    }
}
