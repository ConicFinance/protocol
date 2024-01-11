// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@chainlink/contracts/Denominations.sol";

import "../../interfaces/IOracle.sol";

import {IAggregatorV3Interface} from "./ChainlinkOracle.sol";

contract FrxETHPriceOracle is IOracle {
    address public constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    uint256 public constant ETH_USD_FEED_MULTIPLIER = 10 ** 8; // ETH/USD feed has 8 decimals

    address public constant FRAX_ETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant FRAX_ETH_ETH_FEED = 0xC58F3385FBc1C8AD2c0C9a061D7c13b141D7A5Df;

    uint256 public constant HEARTBEAT = 90_000; // FRAX_ETH_ETH_FEED.maximumOracleDelay = 25 hours

    function getUSDPrice(address token) external view override returns (uint256) {
        require(token == FRAX_ETH, "only supports FRXETH");
        uint256 ethPrice_ = _getPrice(ETH_USD_FEED);
        uint256 frxEthEthPrice_ = _getPrice(FRAX_ETH_ETH_FEED);
        return (ethPrice_ * frxEthEthPrice_) / ETH_USD_FEED_MULTIPLIER;
    }

    function _getPrice(address feed) internal view returns (uint256) {
        IAggregatorV3Interface feed_ = IAggregatorV3Interface(feed);
        (, int256 price_, , uint256 updatedAt_, ) = feed_.latestRoundData();
        require(price_ > 0, "negative price");
        require(updatedAt_ >= block.timestamp - HEARTBEAT, "price too old");
        return uint256(price_);
    }

    function isTokenSupported(address token) external pure override returns (bool) {
        return token == FRAX_ETH;
    }
}
