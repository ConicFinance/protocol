// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../../interfaces/tokenomics/IBonding.sol";

contract MockBonding is IBonding {
    function startBonding() external override {}

    function setCncStartPrice(uint256) external override {}

    function setCncPriceIncreaseFactor(uint256) external override {}

    function setMinBondingAmount(uint256) external override {}

    function setDebtPool(address) external override {}

    function bondCncCrvUsd(uint256, uint256, uint64) external pure override returns (uint256) {
        return 0;
    }

    function bondCncCrvUsdFor(
        uint256,
        uint256,
        uint64,
        address
    ) public pure override returns (uint256) {
        return 0;
    }

    function recoverRemainingCNC() external override {}

    function claimStream() external override {}

    function streamCheckpoint() external override {}

    function claimFeesForDebtPool() external override {}

    function accountCheckpoint(address account) external override {}

    function computeCurrentCncBondPrice() external pure override returns (uint256) {
        return 1e18;
    }

    function cncAvailable() external view override returns (uint256) {
        return 0;
    }

    function cncBondPrice() external view override returns (uint256) {
        return 1e18;
    }
}
