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

// TODO: Implement an enforcement for ending the bonding
contract Bonding is IBonding, Ownable {
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant CNC = IERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);

    uint256 public constant MIN_CNC_START_PRICE = 1e18;
    uint256 public constant MAX_CNC_START_PRICE = 20e18;
    uint256 public constant MIN_PRICE_INCREASE_FACTOR = 5e17;

    ICNCLockerV3 public immutable cncLocker;
    IController public immutable controller;
    IConicPool public immutable crvUsdPool;
    IERC20 public immutable underlying;
    address public debtPool;

    uint256 public immutable totalNumberEpochs;
    uint256 public immutable epochDuration;
    uint256 public cncPerEpoch;
    bool public bondingStarted;

    uint256 public cncStartPrice;
    uint256 public cncAvailable;
    uint256 public cncDistributed;
    uint256 public epochStartTime; // start time of the current epoch
    uint256 public lastCncPrice;
    uint256 public epochPriceIncreaseFactor;

    mapping(uint256 => uint256) public assetsInEpoch;
    uint256 public lastStreamUpdate; // last update for asset streaming
    uint256 public lastStreamEpochStartTime;

    mapping(address => uint256) public perAccountStreamIntegral;
    mapping(address => uint256) public perAccountStreamAccrued;
    uint256 public streamIntegral;

    constructor(
        address _cncLocker,
        address _controller,
        address _crvUsdPool,
        uint256 _epochDuration,
        uint256 _totalNumberEpochs
    ) {
        cncLocker = ICNCLockerV3(_cncLocker);
        controller = IController(_controller);
        crvUsdPool = IConicPool(_crvUsdPool);
        underlying = crvUsdPool.underlying();
        totalNumberEpochs = _totalNumberEpochs;
        epochDuration = _epochDuration;
    }

    function startBonding() external override onlyOwner {
        require(!bondingStarted, "bonding already started");
        uint256 cncBalance = CNC.balanceOf(address(this));
        require(cncBalance > 0, "No CNC balance to bond with");

        cncPerEpoch = cncBalance / totalNumberEpochs;

        lastStreamEpochStartTime = block.timestamp;
        lastStreamUpdate = block.timestamp;
        epochStartTime = block.timestamp;

        bondingStarted = true;
        cncAvailable = cncPerEpoch;
        emit BondingStarted(cncBalance, totalNumberEpochs);
    }

    function setCncStartPrice(uint256 _cncStartPrice) external override onlyOwner {
        require(
            _cncStartPrice > MIN_CNC_START_PRICE && _cncStartPrice < MAX_CNC_START_PRICE,
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

    function setDebtPool(address _debtPool) external override onlyOwner {
        debtPool = _debtPool;
        emit DebtPoolSet(_debtPool);
    }

    function bondCrvUsd(
        uint256 lpTokenAmount,
        uint256 minCncReceived,
        uint64 cncLockTime
    ) external override {
        if (!bondingStarted) return;
        _updateAvailableCncAndStartPrice();
        uint256 valueInUSD = _computeLpTokenValueInUsd(lpTokenAmount);
        uint256 currentCncBondPrice = computeCurrentCncBondPrice();
        uint256 cncToReceive = valueInUSD.divDown(currentCncBondPrice);

        require(
            cncToReceive + cncDistributed <= cncAvailable,
            "Not enough CNC currently available"
        );
        require(cncToReceive >= minCncReceived, "Insufficient CNC received");

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
    }

    function claimStream() external override {
        if (!bondingStarted) return;
        checkpointAccount(msg.sender);
        IERC20 lpToken = IERC20(crvUsdPool.lpToken());
        uint256 amount = perAccountStreamAccrued[msg.sender];
        ILpTokenStaker lpTokenStaker = controller.lpTokenStaker();
        lpTokenStaker.unstake(amount, address(crvUsdPool));
        lpToken.safeTransfer(msg.sender, amount);
        perAccountStreamAccrued[msg.sender] = 0;
        emit StreamClaimed(msg.sender, amount);
    }

    function streamCheckpoint() public override {
        if (!bondingStarted) return;

        uint256 streamed = _updateStreamed();
        uint256 totalBoosted = cncLocker.totalBoosted();
        if (totalBoosted > 0) {
            streamIntegral += streamed.divDown(totalBoosted);
        }
    }

    function checkpointAccount(address account) public override {
        if (!bondingStarted) return;
        streamCheckpoint();
        uint256 accountBoostedBalance = cncLocker.totalRewardsBoost(account);
        perAccountStreamAccrued[account] += accountBoostedBalance.mulDown(
            streamIntegral - perAccountStreamIntegral[account]
        );
        perAccountStreamIntegral[account] = streamIntegral;
    }

    function computeCurrentCncBondPrice() public view override returns (uint256) {
        uint256 discountFactor = ScaledMath.ONE -
            (block.timestamp - epochStartTime).divDown(epochDuration);
        return cncStartPrice.mulDown(discountFactor);
    }

    function _updateStreamed() internal returns (uint256) {
        uint256 streamed;
        uint256 streamedInEpoch;
        while (block.timestamp >= lastStreamEpochStartTime + epochDuration) {
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

    function _computeLpTokenValueInUsd(uint256 lpTokenAmount) internal view returns (uint256) {
        uint256 valueInUnderlying = crvUsdPool.exchangeRate().mulDown(lpTokenAmount);
        uint256 underlyingExchangeRate = IOracle(controller.priceOracle()).getUSDPrice(
            address(underlying)
        );
        return underlyingExchangeRate.mulDown(valueInUnderlying);
    }
}
