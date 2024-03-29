// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BaseConicPool.sol";
import "../interfaces/IPoolAdapter.sol";

contract ConicEthPool is BaseConicPool {
    using EnumerableSet for EnumerableSet.AddressSet;
    using ScaledMath for uint256;

    constructor(
        address _underlying,
        IRewardManager _rewardManager,
        address _controller,
        string memory _lpTokenName,
        string memory _symbol,
        address _cvx,
        address _crv
    ) BaseConicPool(_underlying, _rewardManager, _controller, _lpTokenName, _symbol, _cvx, _crv) {}

    function _updatePriceCache() internal override {
        address[] memory underlyings = getAllUnderlyingCoins();
        IOracle priceOracle_ = controller.priceOracle();
        uint256 ethUsdPrice_ = priceOracle_.getUSDPrice(address(0));
        for (uint256 i; i < underlyings.length; i++) {
            address coin = underlyings[i];
            uint256 priceInUsd_ = priceOracle_.getUSDPrice(coin);
            _cachedPrices[coin] = priceInUsd_.divDown(ethUsdPrice_);
        }
    }

    function _isAssetDepegged(address asset_) internal view override returns (bool) {
        // ETH has no sense of peg per se, so always return false for it
        if (asset_ == address(underlying)) return false;

        uint256 cachedPrice_ = _cachedPrices[asset_];
        IOracle priceOracle_ = controller.priceOracle();
        uint256 ethUsdPrice_ = priceOracle_.getUSDPrice(address(0));
        uint256 currentPriceUsd_ = priceOracle_.getUSDPrice(asset_);
        uint256 currentPrice_ = currentPriceUsd_.divDown(ethUsdPrice_);
        uint256 priceDiff_ = cachedPrice_.absSub(currentPrice_);
        uint256 priceDiffPercent_ = priceDiff_.divDown(cachedPrice_);
        return priceDiffPercent_ > depegThreshold;
    }

    function runSanityChecks() public override {
        ICurveRegistryCache curveRegistryCache = controller.curveRegistryCache();
        address[] memory pools = weightManager.allPools();
        for (uint256 i; i < pools.length; i++) {
            address pool_ = pools[i];
            controller.poolAdapterFor(pool_).executeSanityCheck(pool_);
            address basePool = curveRegistryCache.basePool(pool_);
            if (basePool != address(0)) {
                controller.poolAdapterFor(basePool).executeSanityCheck(basePool);
            }
        }
    }
}
