// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IConicPoolWeightManagement.sol";

interface IConicPoolWeightManager is IConicPoolWeightManagement {
    function getDepositPool(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 maxDeviation
    ) external view returns (uint256 poolIndex, uint256 maxDepositAmount);

    function getWithdrawPool(
        uint256 totalUnderlying_,
        uint256[] memory allocatedPerPool,
        uint256 maxDeviation
    ) external view returns (uint256 withdrawPoolIndex, uint256 maxWithdrawalAmount);

    function computeTotalDeviation(
        uint256 allocatedUnderlying_,
        uint256[] memory perPoolAllocations_
    ) external view returns (uint256);

    function isBalanced(
        uint256[] memory allocatedPerPool_,
        uint256 totalAllocated_,
        uint256 maxDeviation
    ) external view returns (bool);
}
