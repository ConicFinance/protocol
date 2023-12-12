// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/tokenomics/IBonding.sol";
import "../../interfaces/tokenomics/ICNCLockerV3.sol";
import "../../interfaces/pools/IRewardManager.sol";
import "../../interfaces/tokenomics/ILpTokenStaker.sol";
import "../../interfaces/IController.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/pools/IConicPool.sol";

import "../../libraries/ScaledMath.sol";

contract Bonding is IBonding, Ownable {
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant CNC = IERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);

    // The price is set in terms of LP tokens, not USD
    uint256 public constant MAX_CNC_START_PRICE = 20e18;
    uint256 public constant MIN_CNC_START_PRICE = 1e18;
    uint256 public constant MIN_PRICE_INCREASE_FACTOR = 5e17;
    uint256 public constant MAX_MIN_BONDING_AMOUNT = 1_000e18;

    ICNCLockerV3 public immutable cncLocker;
    IController public immutable controller;
    IConicPool public immutable crvUsdPool;
    IERC20 public immutable underlying;
    address public immutable treasury;

    address public debtPool;

    uint256 public immutable totalNumberEpochs;
    uint256 public immutable epochDuration;
    uint256 public cncPerEpoch;
    bool public bondingStarted;
    uint256 public bondingEndTime;

    uint256 public cncStartPrice;
    uint256 public cncAvailable;
    uint256 public cncDistributed;
    uint256 public epochStartTime; // start time of the current epoch
    uint256 public lastCncPrice;
    uint256 public epochPriceIncreaseFactor;
    uint256 public minBondingAmount;

    mapping(uint256 => uint256) public assetsInEpoch;
    uint256 public lastStreamUpdate; // last update for asset streaming
    uint256 public lastStreamEpochStartTime;

    mapping(address => uint256) public perAccountStreamIntegral;
    mapping(address => uint256) public perAccountStreamAccrued;
    uint256 public streamIntegral;

    constructor(
        address _cncLocker,
        address _controller,
        address _treasury,
        address _crvUsdPool,
        uint256 _epochDuration,
        uint256 _totalNumberEpochs
    ) {
        require(_totalNumberEpochs > 0, "total number of epochs must be positive");
        require(_epochDuration > 0, "epoch duration must be positive");

        cncLocker = ICNCLockerV3(_cncLocker);
        controller = IController(_controller);
        treasury = _treasury;
        crvUsdPool = IConicPool(_crvUsdPool);
        underlying = crvUsdPool.underlying();
        totalNumberEpochs = _totalNumberEpochs;
        epochDuration = _epochDuration;
    }

    function startBonding() external override onlyOwner {
        require(!bondingStarted, "bonding already started");
        require(epochPriceIncreaseFactor > 0, "Epoch price increase factor has not been set");
        require(cncStartPrice > 0, "CNC start price not set");
        uint256 cncBalance = CNC.balanceOf(address(this));
        require(cncBalance > 0, "no CNC balance to bond with");

        cncPerEpoch = cncBalance / totalNumberEpochs;

        lastStreamEpochStartTime = block.timestamp;
        lastStreamUpdate = block.timestamp;
        epochStartTime = block.timestamp;
        bondingEndTime = block.timestamp + epochDuration * totalNumberEpochs;

        bondingStarted = true;
        cncAvailable = cncPerEpoch;
        emit BondingStarted(cncBalance, totalNumberEpochs);
    }

    function setCncStartPrice(uint256 _cncStartPrice) external override onlyOwner {
        require(
            _cncStartPrice >= MIN_CNC_START_PRICE && _cncStartPrice <= MAX_CNC_START_PRICE,
            "CNC start price not within permitted range"
        );
        cncStartPrice = _cncStartPrice;
        lastCncPrice = _cncStartPrice;
        emit CncStartPriceSet(_cncStartPrice);
    }

    function setCncPriceIncreaseFactor(uint256 _priceIncreaseFactor) external override onlyOwner {
        require(_priceIncreaseFactor >= MIN_PRICE_INCREASE_FACTOR, "Increase factor too low.");
        epochPriceIncreaseFactor = _priceIncreaseFactor;
        emit PriceIncreaseFactorSet(_priceIncreaseFactor);
    }

    function setMinBondingAmount(uint256 _minBondingAmount) external override onlyOwner {
        require(_minBondingAmount <= MAX_MIN_BONDING_AMOUNT, "Min. bonding amount is too high");
        minBondingAmount = _minBondingAmount;
        emit MinBondingAmountSet(_minBondingAmount);
    }

    function setDebtPool(address _debtPool) external override onlyOwner {
        debtPool = _debtPool;
        emit DebtPoolSet(_debtPool);
    }

    function bondCncCrvUsd(
        uint256 lpTokenAmount,
        uint256 minCncReceived,
        uint64 cncLockTime
    ) external override returns (uint256) {
        if (!bondingStarted) return 0;
        require(block.timestamp <= bondingEndTime, "Bonding has ended");
        require(lpTokenAmount > minBondingAmount, "Min. bonding amount not reached");
        _updateAvailableCncAndStartPrice();
        uint256 currentCncBondPrice = computeCurrentCncBondPrice();
        uint256 cncToReceive = lpTokenAmount.divDown(currentCncBondPrice);

        require(
            cncToReceive + cncDistributed <= cncAvailable,
            "Not enough CNC currently available"
        );
        require(cncToReceive >= minCncReceived, "Insufficient CNC received");

        // Checkpoint to set user integrals etc.
        _accountCheckpoint(msg.sender);

        IERC20 lpToken = IERC20(crvUsdPool.lpToken());
        lpToken.safeTransferFrom(msg.sender, address(this), lpTokenAmount);
        ILpTokenStaker lpTokenStaker = controller.lpTokenStaker();
        lpToken.approve(address(lpTokenStaker), lpTokenAmount);
        lpTokenStaker.stake(lpTokenAmount, address(crvUsdPool));

        // Schedule assets for streaming in the next epoch
        assetsInEpoch[epochStartTime + epochDuration] += lpTokenAmount;
        cncDistributed += cncToReceive;
        CNC.approve(address(cncLocker), cncToReceive);
        cncLocker.lockFor(cncToReceive, cncLockTime, false, msg.sender);

        lastCncPrice = currentCncBondPrice < MIN_CNC_START_PRICE
            ? MIN_CNC_START_PRICE
            : currentCncBondPrice;

        emit Bonded(msg.sender, lpTokenAmount, cncToReceive, cncLockTime);
        return cncToReceive;
    }

    function claimStream() external override {
        if (!bondingStarted) return;
        _accountCheckpoint(msg.sender);
        IERC20 lpToken = IERC20(crvUsdPool.lpToken());
        uint256 amount = perAccountStreamAccrued[msg.sender];
        require(amount > 0, "no balance");
        ILpTokenStaker lpTokenStaker = controller.lpTokenStaker();
        lpTokenStaker.unstake(amount, address(crvUsdPool));
        lpToken.safeTransfer(msg.sender, amount);
        perAccountStreamAccrued[msg.sender] = 0;
        emit StreamClaimed(msg.sender, amount);
    }

    function claimFeesForDebtPool() external override {
        require(address(debtPool) != address(0), "No debt pool set");
        uint256 cncBefore = CNC.balanceOf(address(this));
        crvUsdPool.rewardManager().claimEarnings();
        uint256 cncAmount = CNC.balanceOf(address(this)) - cncBefore;
        uint256 crvAmount = CRV.balanceOf(address(this));
        uint256 cvxAmount = CVX.balanceOf(address(this));
        CRV.safeTransfer(address(debtPool), crvAmount);
        CVX.safeTransfer(address(debtPool), cvxAmount);
        CNC.safeTransfer(address(debtPool), cncAmount);
        emit DebtPoolFeesClaimed(crvAmount, cvxAmount, cncAmount);
    }

    function recoverRemainingCNC() external override onlyOwner {
        require(block.timestamp > bondingEndTime, "Bonding has not yet ended");
        uint256 amount = CNC.balanceOf(address(this));
        CNC.safeTransfer(treasury, amount);
        emit RemainingCNCRecovered(amount);
    }

    function streamCheckpoint() public override {
        if (!bondingStarted) return;
        _streamCheckpoint();
    }

    function accountCheckpoint(address account) public override {
        if (!bondingStarted) return;
        _accountCheckpoint(account);
    }

    function computeCurrentCncBondPrice() public view override returns (uint256) {
        uint256 discountFactor = ScaledMath.ONE -
            (block.timestamp - epochStartTime).divDown(epochDuration);
        return cncStartPrice.mulDown(discountFactor);
    }

    function _accountCheckpoint(address account) internal {
        _streamCheckpoint();
        uint256 accountBoostedBalance = cncLocker.totalStreamBoost(account);
        perAccountStreamAccrued[account] += accountBoostedBalance.mulDown(
            streamIntegral - perAccountStreamIntegral[account]
        );
        perAccountStreamIntegral[account] = streamIntegral;
    }

    function _streamCheckpoint() internal {
        uint256 streamed = _updateStreamed();
        uint256 totalBoosted = cncLocker.totalBoosted();
        if (totalBoosted > 0) {
            streamIntegral += streamed.divDown(totalBoosted);
        }
    }

    function _updateStreamed() internal returns (uint256) {
        uint256 streamed;
        uint256 streamedInEpoch;
        while (
            (block.timestamp >= lastStreamEpochStartTime + epochDuration) &&
            (lastStreamEpochStartTime < bondingEndTime + epochDuration)
        ) {
            streamedInEpoch = (lastStreamEpochStartTime + epochDuration - lastStreamUpdate)
                .divDown(epochDuration)
                .mulDown(assetsInEpoch[lastStreamEpochStartTime]);
            lastStreamEpochStartTime += epochDuration;
            lastStreamUpdate = lastStreamEpochStartTime;
            streamed += streamedInEpoch;
        }
        streamed += (block.timestamp - lastStreamUpdate).divDown(epochDuration).mulDown(
            assetsInEpoch[lastStreamEpochStartTime]
        );
        lastStreamUpdate = block.timestamp;
        return streamed;
    }

    function _updateAvailableCncAndStartPrice() internal {
        bool priceUpdated;
        while (block.timestamp >= epochStartTime + epochDuration) {
            cncAvailable += cncPerEpoch;
            epochStartTime += epochDuration;
            if (!priceUpdated) {
                cncStartPrice = epochPriceIncreaseFactor.mulDown(lastCncPrice);
                priceUpdated = true;
            }
        }
    }
}
