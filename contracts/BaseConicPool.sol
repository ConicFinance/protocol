// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "../interfaces/pools/IConicPool.sol";
import "../interfaces/pools/IRewardManager.sol";
import "../interfaces/pools/IWithdrawalProcessor.sol";
import "../interfaces/ICurveRegistryCache.sol";
import "../interfaces/tokenomics/IInflationManager.sol";
import "../interfaces/tokenomics/ILpTokenStaker.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/vendor/IBaseRewardPool.sol";

import "./LpToken.sol";
import "./Pausable.sol";
import "./ConicPoolWeightManager.sol";

import "../libraries/ScaledMath.sol";
import "../libraries/ArrayExtensions.sol";

abstract contract BaseConicPool is IConicPool, Pausable {
    using ArrayExtensions for uint256[];
    using ArrayExtensions for address[];
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for ILpToken;
    using ScaledMath for uint256;
    using Address for address;
    using ERC165Checker for address;

    // Avoid stack depth errors
    struct DepositVars {
        uint256 exchangeRate;
        uint256 underlyingBalanceIncrease;
        uint256 mintableUnderlyingAmount;
        uint256 lpReceived;
        uint256 underlyingBalanceBefore;
        uint256 allocatedBalanceBefore;
        uint256[] allocatedPerPoolBefore;
        uint256 underlyingBalanceAfter;
        uint256 allocatedBalanceAfter;
        uint256[] allocatedPerPoolAfter;
    }

    uint256 internal constant _IDLE_RATIO_UPPER_BOUND = 0.2e18;
    uint256 internal constant _MIN_DEPEG_THRESHOLD = 0.01e18;
    uint256 internal constant _MAX_DEPEG_THRESHOLD = 0.1e18;
    uint256 internal constant _MAX_DEVIATION_UPPER_BOUND = 0.2e18;
    uint256 internal constant _TOTAL_UNDERLYING_CACHE_EXPIRY = 3 days;
    uint256 internal constant _MAX_USD_VALUE_FOR_REMOVING_POOL = 100e18;
    uint256 internal constant _MIN_EMERGENCY_REBALANCING_REWARD_FACTOR = 1e18;
    uint256 internal constant _MAX_EMERGENCY_REBALANCING_REWARD_FACTOR = 100e18;

    IERC20 internal immutable CVX;
    IERC20 internal immutable CRV;
    IERC20 internal constant CNC = IERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);
    address internal constant _WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20Metadata public immutable override underlying;
    ILpToken public immutable override lpToken;

    IRewardManager public immutable rewardManager;
    IConicPoolWeightManager public immutable weightManager;

    /// @dev once the deviation gets under this threshold, the reward distribution will be paused
    /// until the next rebalancing. This is expressed as a ratio, scaled with 18 decimals
    uint256 public maxDeviation = 0.02e18; // 2%
    uint256 public maxIdleCurveLpRatio = 0.05e18; // triggers Convex staking when exceeded
    bool public isShutdown;
    uint256 public depegThreshold = 0.03e18; // 3%
    uint256 internal _cacheUpdatedTimestamp;
    uint256 internal _cachedTotalUnderlying;

    /// @dev `true` if the rebalancing rewards are enabled, i.e. can become active
    /// A pool starts rebalancing rewards disabled, and these need to be enabled through governance
    bool public rebalancingRewardsEnabled;

    /// @dev `true` while the reward distribution is active
    bool public rebalancingRewardActive;

    /// @notice the time at which rebalancing rewards have been activated
    uint64 public rebalancingRewardsActivatedAt;

    /// @notice The factor by which the rebalancing reward is multiplied when a pool is depegged
    uint256 public emergencyRebalancingRewardsFactor = 10e18;

    /// @notice The factor by which the rebalancing reward is multiplied
    /// this is 1 (scaled to 18 decimals) for normal rebalancing situations but is set
    /// to `emergencyRebalancingRewardsFactor` when a pool is depegged
    uint256 public rebalancingRewardsFactor;

    /// @dev the absolute value in terms of USD of the total deviation after
    /// the weights have been updated
    uint256 public totalDeviationAfterWeightUpdate;

    mapping(address => uint256) _cachedPrices;

    modifier onlyController() {
        require(msg.sender == address(controller), "not authorized");
        _;
    }

    constructor(
        address _underlying,
        IRewardManager _rewardManager,
        address _controller,
        string memory _lpTokenName,
        string memory _symbol,
        address _cvx,
        address _crv
    ) Pausable(IController(_controller)) {
        require(
            _underlying != _cvx && _underlying != _crv && _underlying != address(CNC),
            "invalid underlying"
        );
        underlying = IERC20Metadata(_underlying);
        uint8 decimals = IERC20Metadata(_underlying).decimals();
        lpToken = new LpToken(_controller, address(this), decimals, _lpTokenName, _symbol);
        rewardManager = _rewardManager;
        weightManager = new ConicPoolWeightManager(
            IController(_controller),
            IERC20Metadata(_underlying)
        );

        CVX = IERC20(_cvx);
        CRV = IERC20(_crv);
        CVX.safeApprove(address(_rewardManager), type(uint256).max);
        CRV.safeApprove(address(_rewardManager), type(uint256).max);
        CNC.safeApprove(address(_rewardManager), type(uint256).max);
    }

    /// @dev We always delegate-call to the Curve handler, which means
    /// that we need to be able to receive the ETH to unwrap it and
    /// send it to the Curve pool, as well as to receive it back from
    /// the Curve pool when withdrawing
    receive() external payable {
        require(address(underlying) == _WETH_ADDRESS, "not WETH pool");
    }

    /// @notice Deposit underlying on behalf of someone
    /// @param underlyingAmount Amount of underlying to deposit
    /// @param minLpReceived The minimum amount of LP to accept from the deposit
    /// @return lpReceived The amount of LP received
    function depositFor(
        address account,
        uint256 underlyingAmount,
        uint256 minLpReceived,
        bool stake
    ) public override notPaused returns (uint256) {
        runSanityChecks();

        DepositVars memory vars;

        // Preparing deposit
        require(!isShutdown, "pool is shut down");
        require(underlyingAmount > 0, "deposit amount cannot be zero");

        _updateAdapterCachedPrices();

        uint256 underlyingPrice_ = controller.priceOracle().getUSDPrice(address(underlying));
        // We use the cached price of LP tokens, which is effectively the latest price
        // because we just updated the cache
        (
            vars.underlyingBalanceBefore,
            vars.allocatedBalanceBefore,
            vars.allocatedPerPoolBefore
        ) = _getTotalAndPerPoolUnderlying(underlyingPrice_, IPoolAdapter.PriceMode.Cached);
        vars.exchangeRate = _exchangeRate(vars.underlyingBalanceBefore);

        // Executing deposit
        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);
        _depositToCurve(
            vars.allocatedBalanceBefore,
            vars.allocatedPerPoolBefore,
            underlying.balanceOf(address(this))
        );

        // Minting LP Tokens
        // We use the minimum between the price of the LP tokens before and after deposit
        (
            vars.underlyingBalanceAfter,
            vars.allocatedBalanceAfter,
            vars.allocatedPerPoolAfter
        ) = _getTotalAndPerPoolUnderlying(underlyingPrice_, IPoolAdapter.PriceMode.Minimum);
        vars.underlyingBalanceIncrease = vars.underlyingBalanceAfter - vars.underlyingBalanceBefore;
        vars.mintableUnderlyingAmount = _min(underlyingAmount, vars.underlyingBalanceIncrease);
        vars.lpReceived = vars.mintableUnderlyingAmount.divDown(vars.exchangeRate);
        require(vars.lpReceived >= minLpReceived, "too much slippage");

        _cachedTotalUnderlying = vars.underlyingBalanceAfter;
        _cacheUpdatedTimestamp = block.timestamp;

        if (stake) {
            lpToken.mint(address(this), vars.lpReceived, account);
            ILpTokenStaker lpTokenStaker = controller.lpTokenStaker();
            lpToken.forceApprove(address(lpTokenStaker), vars.lpReceived);
            lpTokenStaker.stakeFor(vars.lpReceived, address(this), account);
        } else {
            lpToken.mint(account, vars.lpReceived, account);
        }

        _handleRebalancingRewards(
            account,
            vars.allocatedBalanceBefore,
            vars.allocatedPerPoolBefore,
            vars.allocatedBalanceAfter,
            vars.allocatedPerPoolAfter
        );

        emit Deposit(msg.sender, account, underlyingAmount, vars.lpReceived);
        return vars.lpReceived;
    }

    /// @notice Deposit underlying
    /// @param underlyingAmount Amount of underlying to deposit
    /// @param minLpReceived The minimum amoun of LP to accept from the deposit
    /// @return lpReceived The amount of LP received
    function deposit(
        uint256 underlyingAmount,
        uint256 minLpReceived
    ) external override returns (uint256) {
        return depositFor(msg.sender, underlyingAmount, minLpReceived, true);
    }

    /// @notice Deposit underlying
    /// @param underlyingAmount Amount of underlying to deposit
    /// @param minLpReceived The minimum amoun of LP to accept from the deposit
    /// @param stake Whether or not to stake in the LpTokenStaker
    /// @return lpReceived The amount of LP received
    function deposit(
        uint256 underlyingAmount,
        uint256 minLpReceived,
        bool stake
    ) external override returns (uint256) {
        return depositFor(msg.sender, underlyingAmount, minLpReceived, stake);
    }

    function _depositToCurve(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 underlyingAmount_
    ) internal {
        uint256 depositsRemaining_ = underlyingAmount_;
        uint256 totalAfterDeposit_ = totalUnderlying_ + underlyingAmount_;

        // NOTE: avoid modifying `allocatedPerPool`
        uint256[] memory allocatedPerPoolCopy = allocatedPerPool.copy();

        while (depositsRemaining_ > 0) {
            (uint256 poolIndex_, uint256 maxDeposit_) = weightManager.getDepositPool(
                totalAfterDeposit_,
                allocatedPerPoolCopy,
                _getMaxDeviation()
            );
            // account for rounding errors
            if (depositsRemaining_ < maxDeposit_ + 1e2) {
                maxDeposit_ = depositsRemaining_;
            }

            address pool_ = weightManager.getPoolAtIndex(poolIndex_);

            // Depositing into least balanced pool
            uint256 toDeposit_ = _min(depositsRemaining_, maxDeposit_);
            address poolAdapter = address(controller.poolAdapterFor(pool_));
            poolAdapter.functionDelegateCall(
                abi.encodeWithSignature(
                    "deposit(address,address,uint256)",
                    pool_,
                    address(underlying),
                    toDeposit_
                )
            );

            depositsRemaining_ -= toDeposit_;
            allocatedPerPoolCopy[poolIndex_] += toDeposit_;
        }
    }

    /// @notice Get current underlying balance of pool
    function totalUnderlying() public view virtual returns (uint256) {
        (uint256 totalUnderlying_, , ) = getTotalAndPerPoolUnderlying();

        return totalUnderlying_;
    }

    function updateRewardSpendingApproval(address token, bool approved) external {
        require(msg.sender == address(rewardManager), "not authorized");
        uint256 amount = approved ? type(uint256).max : 0;
        IERC20(token).safeApprove(address(rewardManager), amount);
    }

    function _exchangeRate(uint256 totalUnderlying_) internal view returns (uint256) {
        uint256 lpSupply = lpToken.totalSupply();
        if (lpSupply == 0 || totalUnderlying_ == 0) return ScaledMath.ONE;

        return totalUnderlying_.divDown(lpSupply);
    }

    /// @notice Get current exchange rate for the pool's LP token to the underlying
    function exchangeRate() public view virtual override returns (uint256) {
        return _exchangeRate(totalUnderlying());
    }

    /// @notice Get current exchange rate for the pool's LP token to USD
    /// @dev This is using the cached total underlying value, so is not precisely accurate.
    function usdExchangeRate() external view virtual override returns (uint256) {
        uint256 underlyingPrice = controller.priceOracle().getUSDPrice(address(underlying));
        return _exchangeRate(cachedTotalUnderlying()).mulDown(underlyingPrice);
    }

    /// @notice Unstake LP Tokens and withdraw underlying
    /// @param conicLpAmount Amount of LP tokens to burn
    /// @param minUnderlyingReceived Minimum amount of underlying to redeem
    /// This should always be set to a reasonable value (e.g. 2%), otherwise
    /// the user withdrawing could be forced into paying a withdrawal penalty fee
    /// by another user
    /// @return uint256 Total underlying withdrawn
    function unstakeAndWithdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived,
        address to
    ) public override returns (uint256) {
        controller.lpTokenStaker().unstakeFrom(conicLpAmount, msg.sender);
        return withdraw(conicLpAmount, minUnderlyingReceived, to);
    }

    function unstakeAndWithdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived
    ) external returns (uint256) {
        return unstakeAndWithdraw(conicLpAmount, minUnderlyingReceived, msg.sender);
    }

    function withdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived
    ) public override returns (uint256) {
        return withdraw(conicLpAmount, minUnderlyingReceived, msg.sender);
    }

    /// @notice Withdraw underlying
    /// @param conicLpAmount Amount of LP tokens to burn
    /// @param minUnderlyingReceived Minimum amount of underlying to redeem
    /// This should always be set to a reasonable value (e.g. 2%), otherwise
    /// the user withdrawing could be forced into paying a withdrawal penalty fee
    /// by another user
    /// @return uint256 Total underlying withdrawn
    function withdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived,
        address to
    ) public override returns (uint256) {
        runSanityChecks();

        // Preparing Withdrawals
        require(lpToken.balanceOf(msg.sender) >= conicLpAmount, "insufficient balance");
        uint256 underlyingBalanceBefore_ = underlying.balanceOf(address(this));

        // Processing Withdrawals
        (
            uint256 totalUnderlying_,
            uint256 allocatedUnderlying_,
            uint256[] memory allocatedPerPool
        ) = getTotalAndPerPoolUnderlying();
        uint256 underlyingToReceive_ = conicLpAmount.mulDown(_exchangeRate(totalUnderlying_));
        {
            if (underlyingBalanceBefore_ < underlyingToReceive_) {
                uint256 underlyingToWithdraw_ = underlyingToReceive_ - underlyingBalanceBefore_;
                _withdrawFromCurve(allocatedUnderlying_, allocatedPerPool, underlyingToWithdraw_);
            }
        }

        // Sending Underlying and burning LP Tokens
        uint256 underlyingWithdrawn_ = _min(
            underlying.balanceOf(address(this)),
            underlyingToReceive_
        );
        require(underlyingWithdrawn_ >= minUnderlyingReceived, "too much slippage");
        lpToken.burn(msg.sender, conicLpAmount, msg.sender);
        underlying.safeTransfer(to, underlyingWithdrawn_);

        _cachedTotalUnderlying = totalUnderlying_ - underlyingWithdrawn_;
        _cacheUpdatedTimestamp = block.timestamp;

        // state has already been updated, so no need to worry about re-entrancy
        if (to.supportsInterface(type(IWithdrawalProcessor).interfaceId)) {
            IWithdrawalProcessor(to).processWithdrawal(msg.sender, underlyingWithdrawn_);
        }

        emit Withdraw(msg.sender, underlyingWithdrawn_);
        return underlyingWithdrawn_;
    }

    function _withdrawFromCurve(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 amount_
    ) internal {
        uint256 withdrawalsRemaining_ = amount_;
        uint256 totalAfterWithdrawal_ = totalUnderlying_ - amount_;

        // NOTE: avoid modifying `allocatedPerPool`
        uint256[] memory allocatedPerPoolCopy = allocatedPerPool.copy();

        while (withdrawalsRemaining_ > 0) {
            (uint256 poolIndex_, uint256 maxWithdrawal_) = weightManager.getWithdrawPool(
                totalAfterWithdrawal_,
                allocatedPerPoolCopy,
                _getMaxDeviation()
            );
            address pool_ = weightManager.getPoolAtIndex(poolIndex_);

            // Withdrawing from least balanced pool
            uint256 toWithdraw_ = _min(withdrawalsRemaining_, maxWithdrawal_);

            address poolAdapter = address(controller.poolAdapterFor(pool_));
            poolAdapter.functionDelegateCall(
                abi.encodeWithSignature(
                    "withdraw(address,address,uint256)",
                    pool_,
                    underlying,
                    toWithdraw_
                )
            );
            withdrawalsRemaining_ -= toWithdraw_;
            allocatedPerPoolCopy[poolIndex_] -= toWithdraw_;
        }
    }

    function allPools() external view override returns (address[] memory) {
        return weightManager.allPools();
    }

    function poolsCount() external view override returns (uint256) {
        return weightManager.poolsCount();
    }

    function getPoolAtIndex(uint256 _index) external view override returns (address) {
        return weightManager.getPoolAtIndex(_index);
    }

    function isRegisteredPool(address _pool) external view returns (bool) {
        return weightManager.isRegisteredPool(_pool);
    }

    // Controller and Admin functions

    function addPool(address _pool) external override onlyOwner {
        weightManager.addPool(_pool);
        address booster = controller.convexBooster();
        address lpToken_ = controller.poolAdapterFor(_pool).lpToken(_pool);
        IERC20(lpToken_).safeApprove(booster, type(uint256).max);
    }

    function removePool(address _pool) external override onlyOwner {
        weightManager.removePool(_pool);
        address booster = controller.convexBooster();
        address lpToken_ = controller.poolAdapterFor(_pool).lpToken(_pool);
        IERC20(lpToken_).safeApprove(booster, 0);
    }

    function updateWeights(PoolWeight[] memory poolWeights) external onlyController {
        runSanityChecks();
        weightManager.updateWeights(poolWeights);

        (
            uint256 totalUnderlying_,
            uint256 totalAllocated,
            uint256[] memory allocatedPerPool
        ) = getTotalAndPerPoolUnderlying();

        uint256 totalDeviation = weightManager.computeTotalDeviation(
            totalUnderlying_,
            allocatedPerPool
        );
        totalDeviationAfterWeightUpdate = totalDeviation;
        rebalancingRewardActive =
            rebalancingRewardsEnabled &&
            !_isBalanced(allocatedPerPool, totalAllocated);
        rebalancingRewardsFactor = ScaledMath.ONE;
        rebalancingRewardsActivatedAt = uint64(block.timestamp);

        // Updating price cache for all pools
        // Used for seeing if a pool has depegged
        _updatePriceCache();
    }

    function shutdownPool() external override onlyController {
        require(!isShutdown, "pool already shut down");
        isShutdown = true;
        emit Shutdown();
    }

    function updateDepegThreshold(uint256 newDepegThreshold_) external onlyOwner {
        require(newDepegThreshold_ >= _MIN_DEPEG_THRESHOLD, "invalid depeg threshold");
        require(newDepegThreshold_ <= _MAX_DEPEG_THRESHOLD, "invalid depeg threshold");
        require(newDepegThreshold_ != depegThreshold, "same as current");
        depegThreshold = newDepegThreshold_;
        emit DepegThresholdUpdated(newDepegThreshold_);
    }

    /// @notice Called when an underlying of a Curve Pool has depegged and we want to exit the pool.
    /// Will check if a coin has depegged, and will revert if not.
    /// Sets the weight of the Curve Pool to 0, and re-enables CNC rewards for deposits.
    /// @dev Cannot be called if the underlying of this pool itself has depegged.
    /// @param curvePool_ The Curve Pool to handle.
    function handleDepeggedCurvePool(address curvePool_) external override {
        runSanityChecks();

        require(!_isAssetDepegged(address(underlying)), "underlying is depegged");
        require(_isPoolDepegged(curvePool_), "pool is not depegged");

        weightManager.handleDepeggedCurvePool(curvePool_);

        // Updating total deviation
        (
            uint256 totalUnderlying_,
            ,
            uint256[] memory allocatedPerPool
        ) = getTotalAndPerPoolUnderlying();
        uint256 totalDeviation = weightManager.computeTotalDeviation(
            totalUnderlying_,
            allocatedPerPool
        );
        totalDeviationAfterWeightUpdate = totalDeviation;

        if (rebalancingRewardsEnabled) {
            IPoolAdapter poolAdapter = controller.poolAdapterFor(curvePool_);
            uint256 usdValue = poolAdapter.computePoolValueInUSD(address(this), curvePool_);
            if (usdValue > _MAX_USD_VALUE_FOR_REMOVING_POOL) {
                // if the rebalancing rewards were already active
                // we reset the activated at because the rewards factor is now increased
                rebalancingRewardsActivatedAt = uint64(block.timestamp);
                rebalancingRewardsFactor = emergencyRebalancingRewardsFactor;
                rebalancingRewardActive = true;
            }
        }

        emit HandledDepeggedCurvePool(curvePool_);
    }

    /**
     * @notice Allows anyone to set the weight of a Curve pool to 0 if the Convex pool for the
     * associated PID has been shut down. This is a very unlikely outcome and the method does
     * not reenable rebalancing rewards.
     * @param curvePool_ Curve pool for which the Convex PID is invalid (has been shut down)
     */
    function handleInvalidConvexPid(address curvePool_) external override returns (uint256) {
        runSanityChecks();
        uint256 pid = weightManager.handleInvalidConvexPid(curvePool_);
        emit HandledInvalidConvexPid(curvePool_, pid);
        return pid;
    }

    function setMaxIdleCurveLpRatio(uint256 maxIdleCurveLpRatio_) external onlyOwner {
        require(maxIdleCurveLpRatio != maxIdleCurveLpRatio_, "same as current");
        require(maxIdleCurveLpRatio_ <= _IDLE_RATIO_UPPER_BOUND, "ratio exceeds upper bound");
        maxIdleCurveLpRatio = maxIdleCurveLpRatio_;
        emit NewMaxIdleCurveLpRatio(maxIdleCurveLpRatio_);
    }

    function setMaxDeviation(uint256 maxDeviation_) external override onlyOwner {
        require(maxDeviation != maxDeviation_, "same as current");
        require(maxDeviation_ <= _MAX_DEVIATION_UPPER_BOUND, "deviation exceeds upper bound");
        maxDeviation = maxDeviation_;
        emit MaxDeviationUpdated(maxDeviation_);
    }

    function getWeight(address curvePool) external view override returns (uint256) {
        return weightManager.getWeight(curvePool);
    }

    function getWeights() external view override returns (PoolWeight[] memory) {
        return weightManager.getWeights();
    }

    function getAllocatedUnderlying() external view override returns (PoolWithAmount[] memory) {
        address[] memory pools = weightManager.allPools();
        PoolWithAmount[] memory perPoolAllocated = new PoolWithAmount[](pools.length);
        (, , uint256[] memory allocated) = getTotalAndPerPoolUnderlying();

        for (uint256 i; i < perPoolAllocated.length; i++) {
            perPoolAllocated[i] = PoolWithAmount(pools[i], allocated[i]);
        }
        return perPoolAllocated;
    }

    function computeTotalDeviation() external view override returns (uint256) {
        (
            ,
            uint256 allocatedUnderlying_,
            uint256[] memory perPoolUnderlying
        ) = getTotalAndPerPoolUnderlying();
        return weightManager.computeTotalDeviation(allocatedUnderlying_, perPoolUnderlying);
    }

    function cachedTotalUnderlying() public view virtual override returns (uint256) {
        if (block.timestamp > _cacheUpdatedTimestamp + _TOTAL_UNDERLYING_CACHE_EXPIRY) {
            return totalUnderlying();
        }
        return _cachedTotalUnderlying;
    }

    function getTotalAndPerPoolUnderlying()
        public
        view
        returns (
            uint256 totalUnderlying_,
            uint256 totalAllocated_,
            uint256[] memory perPoolUnderlying_
        )
    {
        uint256 underlyingPrice_ = controller.priceOracle().getUSDPrice(address(underlying));
        return _getTotalAndPerPoolUnderlying(underlyingPrice_, IPoolAdapter.PriceMode.Latest);
    }

    function isBalanced() external view override returns (bool) {
        (
            ,
            uint256 allocatedUnderlying_,
            uint256[] memory allocatedPerPool_
        ) = getTotalAndPerPoolUnderlying();
        return _isBalanced(allocatedPerPool_, allocatedUnderlying_);
    }

    function setRebalancingRewardsEnabled(bool enabled) external override onlyOwner {
        require(rebalancingRewardsEnabled != enabled, "same as current");
        rebalancingRewardsEnabled = enabled;
        emit RebalancingRewardsEnabledSet(enabled);
    }

    function setEmergencyRebalancingRewardFactor(uint256 factor_) external onlyOwner {
        require(factor_ >= _MIN_EMERGENCY_REBALANCING_REWARD_FACTOR, "factor below minimum");
        require(factor_ <= _MAX_EMERGENCY_REBALANCING_REWARD_FACTOR, "factor above maximum");
        require(factor_ != emergencyRebalancingRewardsFactor, "same as current");
        emergencyRebalancingRewardsFactor = factor_;
        emit EmergencyRebalancingRewardFactorUpdated(factor_);
    }

    function _updateAdapterCachedPrices() internal {
        address[] memory pools = weightManager.allPools();
        uint256 poolsLength_ = pools.length;
        for (uint256 i; i < poolsLength_; i++) {
            address pool_ = pools[i];
            IPoolAdapter poolAdapter = controller.poolAdapterFor(pool_);
            poolAdapter.updatePriceCache(pool_);
        }
    }

    /**
     * @notice Returns several values related to the Omnipools's underlying assets.
     * @param underlyingPrice_ Price of the underlying asset in USD
     * @return totalUnderlying_ Total underlying value of the Omnipool
     * @return totalAllocated_ Total underlying value of the Omnipool that is allocated to Curve pools
     * @return perPoolUnderlying_ Array of underlying values of the Omnipool that is allocated to each Curve pool
     */
    function _getTotalAndPerPoolUnderlying(
        uint256 underlyingPrice_,
        IPoolAdapter.PriceMode priceMode
    )
        internal
        view
        returns (
            uint256 totalUnderlying_,
            uint256 totalAllocated_,
            uint256[] memory perPoolUnderlying_
        )
    {
        address[] memory pools = weightManager.allPools();
        uint256 poolsLength_ = pools.length;
        perPoolUnderlying_ = new uint256[](poolsLength_);

        for (uint256 i; i < poolsLength_; i++) {
            address pool_ = pools[i];
            uint256 poolUnderlying_ = controller.poolAdapterFor(pool_).computePoolValueInUnderlying(
                address(this),
                pool_,
                address(underlying),
                underlyingPrice_,
                priceMode
            );
            perPoolUnderlying_[i] = poolUnderlying_;
            totalAllocated_ += poolUnderlying_;
        }
        totalUnderlying_ = totalAllocated_ + underlying.balanceOf(address(this));
    }

    function _handleRebalancingRewards(
        address account,
        uint256 allocatedBalanceBefore_,
        uint256[] memory allocatedPerPoolBefore,
        uint256 allocatedBalanceAfter_,
        uint256[] memory allocatedPerPoolAfter
    ) internal {
        if (!rebalancingRewardActive) return;
        uint256 deviationBefore = weightManager.computeTotalDeviation(
            allocatedBalanceBefore_,
            allocatedPerPoolBefore
        );
        uint256 deviationAfter = weightManager.computeTotalDeviation(
            allocatedBalanceAfter_,
            allocatedPerPoolAfter
        );

        controller.inflationManager().handleRebalancingRewards(
            account,
            deviationBefore,
            deviationAfter
        );

        if (_isBalanced(allocatedPerPoolAfter, allocatedBalanceAfter_)) {
            rebalancingRewardActive = false;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _isBalanced(
        uint256[] memory allocatedPerPool_,
        uint256 totalAllocated_
    ) internal view returns (bool) {
        return weightManager.isBalanced(allocatedPerPool_, totalAllocated_, maxDeviation);
    }

    function getAllUnderlyingCoins() public view returns (address[] memory) {
        address[] memory pools = weightManager.allPools();
        uint256 poolsLength_ = pools.length;
        address[] memory underlyings_ = new address[](0);

        for (uint256 i; i < poolsLength_; i++) {
            address pool_ = pools[i];
            address[] memory coins = controller.poolAdapterFor(pool_).getAllUnderlyingCoins(pool_);
            underlyings_ = underlyings_.concat(coins);
        }
        return underlyings_.removeDuplicates();
    }

    function _isPoolDepegged(address pool_) internal view returns (bool) {
        address[] memory coins = controller.poolAdapterFor(pool_).getAllUnderlyingCoins(pool_);
        for (uint256 i; i < coins.length; i++) {
            address coin = coins[i];
            if (_isAssetDepegged(coin)) return true;
        }
        return false;
    }

    function runSanityChecks() public virtual {}

    function _getMaxDeviation() internal view returns (uint256) {
        return rebalancingRewardActive ? 0 : maxDeviation;
    }

    function _updatePriceCache() internal virtual;

    function _isAssetDepegged(address asset_) internal view virtual returns (bool);
}
