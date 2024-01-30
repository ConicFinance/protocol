// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../libraries/Types.sol";
import "../../libraries/ScaledMath.sol";
import "../../libraries/ScaledMath.sol";
import "../../libraries/CurvePoolUtils.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/IController.sol";
import "../../interfaces/vendor/ICurveFactory.sol";
import "../../interfaces/vendor/ICurvePoolV0.sol";
import "../../interfaces/vendor/ICurvePoolV1.sol";
import "../../interfaces/vendor/ICurveMetaRegistry.sol";

/*
 * This oracle is used for the exchange rate for the Curve Pools supporting Conic LP Tokens.
 * It uses a prepare/execute update pattern to protect against potential sandwich attacks during the update.
 * This should not be considered a general purpose oracle, it is only meant to be used for Curve pools.
 * The prices here will be updated periodically by the Conic team, but may not reflect the current market price.
 */
contract CurveLPOracle is IOracle, Ownable {
    using ScaledMath for uint256;

    event ImbalanceThresholdUpdated(address indexed token, uint256 threshold);
    event InternalImbalanceThresholdUpdated(address indexed token, uint256 threshold);

    uint256 internal constant _MAX_IMBALANCE_BUFFER = 0.1e18;
    mapping(address => uint256) public customImbalanceBuffers;

    /// @notice these are used when the oracle is called internally for pricing metapool base pools
    mapping(address => uint256) public customInternalImbalanceBuffers;

    IController private immutable controller;

    constructor(address controller_) {
        controller = IController(controller_);
    }

    function isTokenSupported(address token) external view override returns (bool) {
        IOracle genericOracle = controller.priceOracle();
        address pool = _getCurvePool(token);
        ICurveRegistryCache curveRegistryCache_ = controller.curveRegistryCache();
        if (!curveRegistryCache_.isRegistered(pool)) return false;
        address[] memory coins = curveRegistryCache_.coins(pool);
        for (uint256 i; i < coins.length; i++) {
            if (!genericOracle.isTokenSupported(coins[i])) return false;
        }
        return true;
    }

    function getUSDPrice(address token) external view returns (uint256) {
        return _getUSDPrice(token, false);
    }

    function _getUSDPrice(address token, bool isInternal) internal view returns (uint256) {
        IGenericOracle genericOracle = controller.priceOracle();

        // Getting the pool data
        address pool = _getCurvePool(token);
        ICurveRegistryCache curveRegistryCache_ = controller.curveRegistryCache();
        require(curveRegistryCache_.isRegistered(pool), "token not supported");
        uint256[] memory decimals = curveRegistryCache_.decimals(pool);
        address[] memory coins = curveRegistryCache_.coins(pool);

        // Adding up the USD value of all the coins in the pool
        uint256 value;
        uint256 numberOfCoins = curveRegistryCache_.nCoins(pool);
        uint256[] memory prices = new uint256[](numberOfCoins);
        uint256[] memory imbalanceBuffers = new uint256[](numberOfCoins);
        for (uint256 i; i < numberOfCoins; i++) {
            address coin = coins[i];
            IOracle oracle = genericOracle.getOracle(coin);

            uint256 imbalanceBuffer = isInternal
                ? customInternalImbalanceBuffers[coin]
                : customImbalanceBuffers[coin];

            uint256 price = address(oracle) == address(this)
                ? _getUSDPrice(coin, true)
                : oracle.getUSDPrice(coin);

            prices[i] = price;
            imbalanceBuffers[i] = imbalanceBuffer;
            require(price > 0, "price is 0");
            uint256 balance = _getBalance(pool, i);
            require(balance > 0, "balance is 0");
            value += balance.convertScale(uint8(decimals[i]), 18).mulDown(price);
        }

        // Verifying the pool is balanced
        CurvePoolUtils.ensurePoolBalanced(
            CurvePoolUtils.PoolMeta({
                pool: pool,
                numberOfCoins: numberOfCoins,
                assetType: curveRegistryCache_.assetType(pool),
                decimals: decimals,
                prices: prices,
                imbalanceBuffers: imbalanceBuffers
            })
        );

        // Returning the value of the pool in USD per LP Token
        return value.divDown(IERC20(token).totalSupply());
    }

    function setImbalanceThreshold(address token, uint256 buffer) external onlyOwner {
        require(buffer <= _MAX_IMBALANCE_BUFFER, "buffer too high");
        customImbalanceBuffers[token] = buffer;
        emit ImbalanceThresholdUpdated(token, buffer);
    }

    function setInternalImbalanceThreshold(address token, uint256 buffer) external onlyOwner {
        require(buffer <= _MAX_IMBALANCE_BUFFER, "buffer too high");
        customInternalImbalanceBuffers[token] = buffer;
        emit InternalImbalanceThresholdUpdated(token, buffer);
    }

    function _getCurvePool(address lpToken_) internal view returns (address) {
        return controller.curveRegistryCache().poolFromLpToken(lpToken_);
    }

    function _getBalance(address curvePool, uint256 index) internal view returns (uint256) {
        if (controller.curveRegistryCache().interfaceVersion(curvePool) == 0) {
            return ICurvePoolV0(curvePool).balances(int128(uint128(index)));
        }
        return ICurvePoolV1(curvePool).balances(index);
    }
}
