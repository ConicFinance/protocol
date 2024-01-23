// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ILpToken.sol";
import "./IRewardManager.sol";
import "../IOracle.sol";
import "../IController.sol";
import "../IPausable.sol";
import "./IConicPoolWeightManagement.sol";

interface IConicPool is IConicPoolWeightManagement, IPausable {
    event Deposit(
        address indexed sender,
        address indexed receiver,
        uint256 depositedAmount,
        uint256 lpReceived
    );
    event Withdraw(address indexed account, uint256 amount);
    event NewWeight(address indexed curvePool, uint256 newWeight);
    event NewMaxIdleCurveLpRatio(uint256 newRatio);
    event ClaimedRewards(uint256 claimedCrv, uint256 claimedCvx);
    event HandledDepeggedCurvePool(address curvePool_);
    event HandledInvalidConvexPid(address curvePool_, uint256 pid_);
    event CurvePoolAdded(address curvePool_);
    event CurvePoolRemoved(address curvePool_);
    event Shutdown();
    event DepegThresholdUpdated(uint256 newThreshold);
    event MaxDeviationUpdated(uint256 newMaxDeviation);
    event RebalancingRewardsEnabledSet(bool enabled);
    event EmergencyRebalancingRewardFactorUpdated(uint256 factor);

    struct PoolWithAmount {
        address poolAddress;
        uint256 amount;
    }

    function underlying() external view returns (IERC20Metadata);

    function lpToken() external view returns (ILpToken);

    function rewardManager() external view returns (IRewardManager);

    function depegThreshold() external view returns (uint256);

    function maxIdleCurveLpRatio() external view returns (uint256);

    function setMaxIdleCurveLpRatio(uint256 value) external;

    function setMaxDeviation(uint256 maxDeviation_) external;

    function updateDepegThreshold(uint256 value) external;

    function depositFor(
        address _account,
        uint256 _amount,
        uint256 _minLpReceived,
        bool stake
    ) external returns (uint256);

    function deposit(uint256 _amount, uint256 _minLpReceived) external returns (uint256);

    function deposit(
        uint256 _amount,
        uint256 _minLpReceived,
        bool stake
    ) external returns (uint256);

    function exchangeRate() external view returns (uint256);

    function usdExchangeRate() external view returns (uint256);

    function unstakeAndWithdraw(uint256 _amount, uint256 _minAmount) external returns (uint256);

    function unstakeAndWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _to
    ) external returns (uint256);

    function withdraw(uint256 _amount, uint256 _minAmount) external returns (uint256);

    function withdraw(uint256 _amount, uint256 _minAmount, address _to) external returns (uint256);

    function getAllocatedUnderlying() external view returns (PoolWithAmount[] memory);

    function rebalancingRewardActive() external view returns (bool);

    function totalDeviationAfterWeightUpdate() external view returns (uint256);

    function computeTotalDeviation() external view returns (uint256);

    /// @notice returns the total amount of funds held by this pool in terms of underlying
    function totalUnderlying() external view returns (uint256);

    function getTotalAndPerPoolUnderlying()
        external
        view
        returns (
            uint256 totalUnderlying_,
            uint256 totalAllocated_,
            uint256[] memory perPoolUnderlying_
        );

    /// @notice same as `totalUnderlying` but returns a cached version
    /// that might be slightly outdated if oracle prices have changed
    /// @dev this is useful in cases where we want to reduce gas usage and do
    /// not need a precise value
    function cachedTotalUnderlying() external view returns (uint256);

    function updateRewardSpendingApproval(address token, bool approved) external;

    function shutdownPool() external;

    function isShutdown() external view returns (bool);

    function isBalanced() external view returns (bool);

    function rebalancingRewardsEnabled() external view returns (bool);

    function setRebalancingRewardsEnabled(bool enabled) external;

    function getAllUnderlyingCoins() external view returns (address[] memory result);

    function rebalancingRewardsFactor() external view returns (uint256);

    function rebalancingRewardsActivatedAt() external view returns (uint64);

    function getWeights() external view returns (PoolWeight[] memory);

    function runSanityChecks() external;
}
