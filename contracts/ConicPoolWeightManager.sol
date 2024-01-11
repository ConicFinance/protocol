// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/pools/IConicPool.sol";
import "../interfaces/pools/IConicPoolWeightManager.sol";

import "../libraries/ScaledMath.sol";

contract ConicPoolWeightManager is IConicPoolWeightManager {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    event CurvePoolAdded(address curvePool_);
    event CurvePoolRemoved(address curvePool_);
    event NewWeight(address indexed curvePool, uint256 newWeight);

    uint256 internal constant _MAX_USD_VALUE_FOR_REMOVING_POOL = 100e18;
    uint256 internal constant _MAX_CURVE_POOLS = 10;

    IConicPool public immutable conicPool;
    IController public immutable controller;
    IERC20Metadata public immutable underlying;

    EnumerableSet.AddressSet internal _pools;
    EnumerableMap.AddressToUintMap internal weights; // liquidity allocation weights

    modifier onlyController() {
        require(msg.sender == address(controller), "not authorized");
        _;
    }

    modifier onlyConicPool() {
        require(msg.sender == address(conicPool), "not authorized");
        _;
    }

    constructor(IController _controller, IERC20Metadata _underlying) {
        conicPool = IConicPool(msg.sender);
        controller = _controller;
        underlying = _underlying;
    }

    function addPool(address _pool) external onlyConicPool {
        require(_pools.length() < _MAX_CURVE_POOLS, "max pools reached");
        require(!_pools.contains(_pool), "pool already added");
        IPoolAdapter poolAdapter = controller.poolAdapterFor(_pool);
        bool supported_ = poolAdapter.supportsAsset(_pool, address(underlying));
        require(supported_, "coin not in pool");
        address lpToken_ = poolAdapter.lpToken(_pool);
        require(controller.priceOracle().isTokenSupported(lpToken_), "cannot price LP Token");

        if (!weights.contains(_pool)) weights.set(_pool, 0);
        require(_pools.add(_pool), "failed to add pool");
        emit CurvePoolAdded(_pool);
    }

    // This requires that the weight of the pool is first set to 0
    function removePool(address _pool) external onlyConicPool {
        require(_pools.contains(_pool), "pool not added");
        require(_pools.length() > 1, "cannot remove last pool");
        IPoolAdapter poolAdapter = controller.poolAdapterFor(_pool);
        uint256 usdValue = poolAdapter.computePoolValueInUSD(address(conicPool), _pool);
        require(usdValue < _MAX_USD_VALUE_FOR_REMOVING_POOL, "pool has allocated funds");
        uint256 weight = weights.get(_pool);
        require(weight == 0, "pool has weight set");
        require(_pools.remove(_pool), "pool not removed");
        require(weights.remove(_pool), "weight not removed");
        emit CurvePoolRemoved(_pool);
    }

    function updateWeights(PoolWeight[] memory poolWeights) external onlyConicPool {
        require(poolWeights.length == _pools.length(), "invalid pool weights");
        uint256 total;

        address previousPool;
        for (uint256 i; i < poolWeights.length; i++) {
            address pool_ = poolWeights[i].poolAddress;
            require(pool_ > previousPool, "pools not sorted");
            require(isRegisteredPool(pool_), "pool is not registered");
            uint256 newWeight = poolWeights[i].weight;
            weights.set(pool_, newWeight);
            emit NewWeight(pool_, newWeight);
            total += newWeight;
            previousPool = pool_;
        }

        require(total == ScaledMath.ONE, "weights do not sum to 1");
    }

    function handleDepeggedCurvePool(address curvePool_) external onlyConicPool {
        // Validation
        require(isRegisteredPool(curvePool_), "pool is not registered");
        require(weights.get(curvePool_) != 0, "pool weight already 0");

        // Set target curve pool weight to 0
        // Scale up other weights to compensate
        _setWeightToZero(curvePool_);
    }

    function handleInvalidConvexPid(address curvePool_) external onlyConicPool returns (uint256) {
        require(isRegisteredPool(curvePool_), "curve pool not registered");
        ICurveRegistryCache registryCache_ = controller.curveRegistryCache();
        uint256 pid = registryCache_.getPid(curvePool_);
        require(registryCache_.isShutdownPid(pid), "convex pool pid is not shut down");
        _setWeightToZero(curvePool_);
        return pid;
    }

    function getDepositPool(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 maxDeviation
    ) external view returns (uint256 poolIndex, uint256 maxDepositAmount) {
        uint256 poolsCount_ = allocatedPerPool.length;
        int256 iPoolIndex = -1;
        for (uint256 i; i < poolsCount_; i++) {
            address pool_ = _pools.at(i);
            uint256 allocatedUnderlying_ = allocatedPerPool[i];
            uint256 weight_ = weights.get(pool_);
            uint256 targetAllocation_ = totalUnderlying_.mulDown(weight_);
            if (allocatedUnderlying_ >= targetAllocation_) continue;
            // Compute max balance with deviation
            uint256 weightWithDeviation_ = weight_.mulDown(ScaledMath.ONE + maxDeviation);
            weightWithDeviation_ = weightWithDeviation_ > ScaledMath.ONE
                ? ScaledMath.ONE
                : weightWithDeviation_;
            uint256 maxBalance_ = totalUnderlying_.mulDown(weightWithDeviation_);
            uint256 maxDepositAmount_ = maxBalance_ - allocatedUnderlying_;
            if (maxDepositAmount_ <= maxDepositAmount) continue;
            maxDepositAmount = maxDepositAmount_;
            iPoolIndex = int256(i);
        }
        require(iPoolIndex > -1, "error retrieving deposit pool");
        poolIndex = uint256(iPoolIndex);
    }

    function getWithdrawPool(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 maxDeviation
    ) external view returns (uint256 withdrawPoolIndex, uint256 maxWithdrawalAmount) {
        uint256 poolsCount_ = allocatedPerPool.length;
        int256 iWithdrawPoolIndex = -1;
        for (uint256 i; i < poolsCount_; i++) {
            address curvePool_ = _pools.at(i);
            uint256 weight_ = weights.get(curvePool_);
            uint256 allocatedUnderlying_ = allocatedPerPool[i];

            // If a pool has a weight of 0,
            // withdraw from it if it has more than the max lp value
            if (weight_ == 0) {
                uint256 price_ = controller.priceOracle().getUSDPrice(address(underlying));
                uint256 allocatedUsd = (price_ * allocatedUnderlying_) /
                    10 ** underlying.decimals();
                if (allocatedUsd >= _MAX_USD_VALUE_FOR_REMOVING_POOL / 2) {
                    return (uint256(i), allocatedUnderlying_);
                }
            }

            uint256 targetAllocation_ = totalUnderlying_.mulDown(weight_);
            if (allocatedUnderlying_ <= targetAllocation_) continue;
            uint256 minBalance_ = targetAllocation_ - targetAllocation_.mulDown(maxDeviation);
            uint256 maxWithdrawalAmount_ = allocatedUnderlying_ - minBalance_;
            if (maxWithdrawalAmount_ <= maxWithdrawalAmount) continue;
            maxWithdrawalAmount = maxWithdrawalAmount_;
            iWithdrawPoolIndex = int256(i);
        }
        require(iWithdrawPoolIndex > -1, "error retrieving withdraw pool");
        withdrawPoolIndex = uint256(iWithdrawPoolIndex);
    }

    function allPools() external view returns (address[] memory) {
        return _pools.values();
    }

    function poolsCount() external view returns (uint256) {
        return _pools.length();
    }

    function getPoolAtIndex(uint256 _index) external view returns (address) {
        return _pools.at(_index);
    }

    function isRegisteredPool(address _pool) public view returns (bool) {
        return _pools.contains(_pool);
    }

    function getWeight(address pool) external view returns (uint256) {
        return weights.get(pool);
    }

    function getWeights() external view returns (IConicPool.PoolWeight[] memory) {
        uint256 length_ = _pools.length();
        IConicPool.PoolWeight[] memory weights_ = new IConicPool.PoolWeight[](length_);
        for (uint256 i; i < length_; i++) {
            (address pool_, uint256 weight_) = weights.at(i);
            weights_[i] = PoolWeight(pool_, weight_);
        }
        return weights_;
    }

    function computeTotalDeviation(
        uint256 allocatedUnderlying_,
        uint256[] memory perPoolAllocations_
    ) external view returns (uint256) {
        uint256 totalDeviation;
        for (uint256 i; i < perPoolAllocations_.length; i++) {
            uint256 weight = weights.get(_pools.at(i));
            uint256 targetAmount = allocatedUnderlying_.mulDown(weight);
            totalDeviation += targetAmount.absSub(perPoolAllocations_[i]);
        }
        return totalDeviation;
    }

    function isBalanced(
        uint256[] memory allocatedPerPool_,
        uint256 totalAllocated_,
        uint256 maxDeviation
    ) external view returns (bool) {
        if (totalAllocated_ == 0) return true;
        for (uint256 i; i < allocatedPerPool_.length; i++) {
            uint256 weight_ = weights.get(_pools.at(i));
            uint256 currentAllocated_ = allocatedPerPool_[i];

            // If a curve pool has a weight of 0,
            if (weight_ == 0) {
                uint256 price_ = controller.priceOracle().getUSDPrice(address(underlying));
                uint256 allocatedUsd_ = (price_ * currentAllocated_) / 10 ** underlying.decimals();
                if (allocatedUsd_ >= _MAX_USD_VALUE_FOR_REMOVING_POOL / 2) {
                    return false;
                }
                continue;
            }

            uint256 targetAmount = totalAllocated_.mulDown(weight_);
            uint256 deviation = targetAmount.absSub(currentAllocated_);
            uint256 deviationRatio = deviation.divDown(targetAmount);

            if (deviationRatio > maxDeviation) return false;
        }
        return true;
    }

    function _setWeightToZero(address zeroedPool) internal {
        uint256 weight_ = weights.get(zeroedPool);
        if (weight_ == 0) return;
        require(weight_ != ScaledMath.ONE, "can't remove last pool");
        uint256 scaleUp_ = ScaledMath.ONE.divDown(ScaledMath.ONE - weights.get(zeroedPool));
        uint256 curvePoolLength_ = _pools.length();

        weights.set(zeroedPool, 0);
        emit NewWeight(zeroedPool, 0);

        address[] memory nonZeroPools = new address[](curvePoolLength_ - 1);
        uint256[] memory nonZeroWeights = new uint256[](curvePoolLength_ - 1);
        uint256 nonZeroPoolsCount;
        for (uint256 i; i < curvePoolLength_; i++) {
            address pool_ = _pools.at(i);
            uint256 currentWeight = weights.get(pool_);
            if (currentWeight == 0) continue;
            nonZeroPools[nonZeroPoolsCount] = pool_;
            nonZeroWeights[nonZeroPoolsCount] = currentWeight;
            nonZeroPoolsCount++;
        }

        uint256 totalWeight;
        for (uint256 i; i < nonZeroPoolsCount; i++) {
            address pool_ = nonZeroPools[i];
            uint256 newWeight_ = nonZeroWeights[i].mulDown(scaleUp_);
            // ensure that the sum of the weights is 1 despite potential rounding errors
            if (i == nonZeroPoolsCount - 1) {
                newWeight_ = ScaledMath.ONE - totalWeight;
            }
            totalWeight += newWeight_;
            weights.set(pool_, newWeight_);
            emit NewWeight(pool_, newWeight_);
        }
    }
}
