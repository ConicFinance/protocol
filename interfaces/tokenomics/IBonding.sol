// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IBonding {
    event CncStartPriceSet(uint256 startPrice);
    event PriceIncreaseFactorSet(uint256 factor);
    event MinBondingAmountSet(uint256 amount);
    event Bonded(
        address indexed account,
        uint256 lpTokenAmount,
        uint256 cncReceived,
        uint256 lockTime
    );
    event DebtPoolSet(address indexed pool);
    event DebtPoolFeesClaimed(uint256 crvAmount, uint256 cvxAmount, uint256 cncAmount);
    event StreamClaimed(address indexed account, uint256 amount);
    event BondingStarted(uint256 amount, uint256 epochs);
    event RemainingCNCRecovered(uint256 amount);

    function startBonding() external;

    function setCncStartPrice(uint256 _cncStartPrice) external;

    function setCncPriceIncreaseFactor(uint256 _priceIncreaseFactor) external;

    function setMinBondingAmount(uint256 _minBondingAmount) external;

    function setDebtPool(address _debtPool) external;

    function bondCncCrvUsd(
        uint256 lpTokenAmount,
        uint256 minCncReceived,
        uint64 cncLockTime
    ) external returns (uint256);

    function recoverRemainingCNC() external;

    function claimStream() external;

    function claimFeesForDebtPool() external;

    function streamCheckpoint() external;

    function accountCheckpoint(address account) external;

    function computeCurrentCncBondPrice() external view returns (uint256);

    function cncAvailable() external view returns (uint256);

    function cncBondPrice() external view returns (uint256);
}
