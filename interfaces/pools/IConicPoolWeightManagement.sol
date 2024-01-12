// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IConicPoolWeightManagement {
    struct PoolWeight {
        address poolAddress;
        uint256 weight;
    }

    function addPool(address pool) external;

    function removePool(address pool) external;

    function updateWeights(PoolWeight[] memory poolWeights) external;

    function handleDepeggedCurvePool(address curvePool_) external;

    function handleInvalidConvexPid(address pool) external returns (uint256);

    function allPools() external view returns (address[] memory);

    function poolsCount() external view returns (uint256);

    function getPoolAtIndex(uint256 _index) external view returns (address);

    function getWeight(address curvePool) external view returns (uint256);

    function getWeights() external view returns (PoolWeight[] memory);

    function isRegisteredPool(address _pool) external view returns (bool);
}
