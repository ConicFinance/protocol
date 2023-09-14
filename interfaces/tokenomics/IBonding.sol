// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IBonding {
    event CncStartPriceSet(uint256 startPrice);
    event PriceIncreaseFactorSet(uint256 factor);
    event Bonded(
        address indexed account,
        uint256 lpTokenAmount,
        uint256 cncReceived,
        uint256 lockTime
    );

    function setCncStartPrice(uint256 _cncStartPrice) external;

    function setCncPriceIncreaseFactor(uint256 _priceIncreaseFactor) external;

    function bondCrvUsd(uint256 lpTokenAmount, uint256 minCncReceived, uint64 cncLockTime) external;

    function computeCurrentCncBondPrice() external view returns (uint256);
}
