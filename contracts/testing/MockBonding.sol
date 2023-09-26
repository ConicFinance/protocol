// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../../interfaces/tokenomics/IBonding.sol";

contract MockBonding is IBonding {
    function startBonding() external override {}

    function setCncStartPrice(uint256 _cncStartPrice) external override {}

    function setCncPriceIncreaseFactor(uint256 _priceIncreaseFactor) external override {}

    function setDebtPool(address _debtPool) external override {}

    function bondCrvUsd(
        uint256 lpTokenAmount,
        uint256 minCncReceived,
        uint64 cncLockTime
    ) external override {}

    function recoverRemainingCNC() external override {}

    function claimStream() external override {}

    function streamCheckpoint() external override {}

    function checkpointAccount(address account) external override {}

    function computeCurrentCncBondPrice() external view override returns (uint256) {
        return 1e18;
    }
}
