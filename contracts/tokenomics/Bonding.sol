// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/tokenomics/IBonding.sol";
import "../../interfaces/tokenomics/ICNCLockerV2.sol";
import "../../interfaces/tokenomics/ILpTokenStaker.sol";
import "../../interfaces/IController.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/pools/IConicPool.sol";

import "../../libraries/ScaledMath.sol";

contract Bonding is IBonding, Ownable {
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MIN_CNC_START_PRICE = 1e18;
    uint256 public constant MAX_CNC_START_PRICE = 20e18;
    uint256 public constant MIN_PRICE_INCREASE_FACTOR = 5e17;

    ICNCLockerV2 public immutable cncLocker;
    IController public immutable controller;
    IConicPool public immutable crvUsdPool;
    IERC20 public immutable underlying;

    uint256 public immutable totalNumberEpochs;
    uint256 public immutable epochDuration;
    uint256 public immutable cncPerEpoch;

    uint256 public cncStartPrice;
    uint256 public cncAvailable;
    uint256 public cncDistributed;
    uint256 public epochStartTime;
    uint256 public lastCncPrice;
    uint256 public epochPriceIncreaseFactor;

    constructor(
        address _cncLocker,
        address _controller,
        address _crvUsdPool,
        uint256 _epochDuration,
        uint256 _totalNumberEpochs,
        uint256 _totalCncAmount
    ) {
        cncLocker = ICNCLockerV2(_cncLocker);
        controller = IController(_controller);
        crvUsdPool = IConicPool(_crvUsdPool);
        underlying = crvUsdPool.underlying();
        totalNumberEpochs = _totalNumberEpochs;
        epochDuration = _epochDuration;
        cncPerEpoch = _totalCncAmount.divDown(_totalNumberEpochs);
    }

    function setCncStartPrice(uint256 _cncStartPrice) external override onlyOwner {
        require(
            _cncStartPrice > MIN_CNC_START_PRICE && _cncStartPrice < MAX_CNC_START_PRICE,
            "CNC start price not within permitted range"
        );
        cncStartPrice = _cncStartPrice;
        emit CncStartPriceSet(_cncStartPrice);
    }

    function setCncPriceIncreaseFactor(uint256 _priceIncreaseFactor) external override onlyOwner {
        require(_priceIncreaseFactor > MIN_PRICE_INCREASE_FACTOR, "Increase factor too low.");
        epochPriceIncreaseFactor = _priceIncreaseFactor;
        emit PriceIncreaseFactorSet(_priceIncreaseFactor);
    }

    function bondCrvUsd(
        uint256 lpTokenAmount,
        uint256 minCncReceived,
        uint64 cncLockTime
    ) external override {
        uint256 valueInUSD = _computeLpTokenValueInUsd(lpTokenAmount);
        uint256 currentCncBondPrice = computeCurrentCncBondPrice();
        uint256 cncToReceive = valueInUSD.divDown(currentCncBondPrice);

        updateAvailableCncAndStartPrice();
        require(
            cncToReceive + cncDistributed <= cncAvailable,
            "Not enough CNC currently available"
        );
        require(cncToReceive >= minCncReceived, "Insufficient CNC received");

        IERC20 lpToken = IERC20(crvUsdPool.lpToken());
        lpToken.safeTransferFrom(msg.sender, address(this), lpTokenAmount);
        ILpTokenStaker lpTokenStaker = controller.lpTokenStaker();
        lpTokenStaker.stake(lpTokenAmount, address(crvUsdPool));

        cncDistributed += cncToReceive;
        cncLocker.lockFor(cncToReceive, cncLockTime, false, msg.sender);

        lastCncPrice = currentCncBondPrice < MIN_CNC_START_PRICE
            ? MIN_CNC_START_PRICE
            : currentCncBondPrice;

        emit Bonded(msg.sender, lpTokenAmount, cncToReceive, cncLockTime);
    }

    function computeCurrentCncBondPrice() public view override returns (uint256) {
        uint256 discountFactor = ScaledMath.ONE -
            (block.timestamp - epochStartTime).divDown(epochDuration);
        return cncStartPrice.mulDown(discountFactor);
    }

    function updateAvailableCncAndStartPrice() internal {
        bool priceUpdated;
        while (block.timestamp > epochStartTime + epochDuration) {
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
