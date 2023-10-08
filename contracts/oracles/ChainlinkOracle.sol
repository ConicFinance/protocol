// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@chainlink/contracts/Denominations.sol";
import "@chainlink/contracts/interfaces/FeedRegistryInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IOracle.sol";

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    /// @notice `getRoundData` and `latestRoundData` should both raise "No data present"
    /// if they do not have data to report, instead of returning unset values
    /// which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract ChainlinkOracle is IOracle, Ownable {
    uint256 public heartbeat = 24 hours;

    FeedRegistryInterface internal constant _feedRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    address internal constant _WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant _CURVE_ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 internal constant _MIN_HEARTBEAT = 6 hours;

    function setHeartbeat(uint256 heartbeat_) external onlyOwner {
        require(heartbeat_ >= _MIN_HEARTBEAT, "heartbeat too low");
        require(heartbeat_ != heartbeat, "same as current");
        heartbeat = heartbeat_;
    }

    function isTokenSupported(address token) external view override returns (bool) {
        if (_isEth(token)) return true;
        try this.getUSDPrice(token) returns (uint256) {
            return true;
        } catch Error(string memory) {
            return false;
        }
    }

    // Prices are always provided with 18 decimals pecision
    function getUSDPrice(address token) external view returns (uint256) {
        return _getPrice(token, Denominations.USD, false);
    }

    function _getPrice(
        address token,
        address denomination,
        bool shouldRevert
    ) internal view returns (uint256) {
        if (_isEth(token)) token = Denominations.ETH;
        try _feedRegistry.latestRoundData(token, denomination) returns (
            uint80,
            int256 price_,
            uint256,
            uint256 updatedAt_,
            uint80
        ) {
            require(updatedAt_ != 0, "round not complete");
            require(price_ > 0, "negative price");
            require(updatedAt_ >= block.timestamp - heartbeat, "price too old");
            return _scaleFrom(uint256(price_), _feedRegistry.decimals(token, denomination));
        } catch Error(string memory reason) {
            if (shouldRevert) revert(reason);

            if (denomination == Denominations.USD) {
                return
                    (_getPrice(token, Denominations.ETH, true) *
                        _getPrice(Denominations.ETH, Denominations.USD, true)) / 1e18;
            }
            return
                (_getPrice(token, Denominations.USD, true) * 1e18) /
                _getPrice(Denominations.ETH, Denominations.USD, true);
        }
    }

    function _scaleFrom(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return value;
        if (decimals > 18) return value / 10 ** (decimals - 18);
        else return value * 10 ** (18 - decimals);
    }

    function _isEth(address token) internal pure returns (bool) {
        return token == address(0) || token == _WETH || token == _CURVE_ETH;
    }
}
