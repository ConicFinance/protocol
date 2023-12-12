// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IPoolAdapter {
    /// @notice This is to set which LP token price the value computation should use
    /// `Latest` uses a freshly computed price
    /// `Cached` uses the price in cache
    /// `Minimum` uses the minimum of these two
    enum PriceMode {
        Latest,
        Cached,
        Minimum
    }

    /// @notice Deposit `underlyingAmount` of `underlying` into `pool`
    /// @dev This function should be written with the assumption that it will be delegate-called into
    function deposit(address pool, address underlying, uint256 underlyingAmount) external;

    /// @notice Withdraw `underlyingAmount` of `underlying` from `pool`
    /// @dev This function should be written with the assumption that it will be delegate-called into
    function withdraw(address pool, address underlying, uint256 underlyingAmount) external;

    /// @notice Returns the amount of of assets that `conicPool` holds in `pool`, in terms of USD
    function computePoolValueInUSD(
        address conicPool,
        address pool
    ) external view returns (uint256 usdAmount);

    /// @notice Updates the price caches of the given pools
    function updatePriceCache(address pool) external;

    /// @notice Returns the amount of of assets that `conicPool` holds in `pool`, in terms of USD
    /// using the given price mode
    function computePoolValueInUSD(
        address conicPool,
        address pool,
        PriceMode priceMode
    ) external view returns (uint256 usdAmount);

    /// @notice Returns the amount of of assets that `conicPool` holds in `pool`, in terms of underlying
    function computePoolValueInUnderlying(
        address conicPool,
        address pool,
        address underlying,
        uint256 underlyingPrice
    ) external view returns (uint256 underlyingAmount);

    /// @notice Returns the amount of of assets that `conicPool` holds in `pool`, in terms of underlying
    /// using the given price mode
    function computePoolValueInUnderlying(
        address conicPool,
        address pool,
        address underlying,
        uint256 underlyingPrice,
        PriceMode priceMode
    ) external view returns (uint256 underlyingAmount);

    /// @notice Claim earnings of `conicPool` from `pool`
    function claimEarnings(address conicPool, address pool) external;

    /// @notice Returns the LP token of a given `pool`
    function lpToken(address pool) external view returns (address);

    /// @notice Returns true if `pool` supports `asset`
    function supportsAsset(address pool, address asset) external view returns (bool);

    /// @notice Returns the amount of CRV earned by `pool` on Convex
    function getCRVEarnedOnConvex(
        address account,
        address curvePool
    ) external view returns (uint256);

    /// @notice Executes a sanity check, e.g. checking for reentrancy
    function executeSanityCheck(address pool) external;

    /// @notice returns all the underlying coins of the pool
    function getAllUnderlyingCoins(address pool) external view returns (address[] memory);
}
