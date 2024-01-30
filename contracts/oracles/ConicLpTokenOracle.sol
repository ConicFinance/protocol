// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../interfaces/pools/IConicPool.sol";

contract ConicLpTokenOracle {
    using EnumerableSet for EnumerableSet.AddressSet;

    event ExchangeRateUpdateRequested(uint256 newExchangeRate);
    event ExchangeRateUpdateExecuted(uint256 oldExchangeRate, uint256 newExchangeRate);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    EnumerableSet.AddressSet internal _admins;

    IConicPool public immutable conicPool;
    IERC20 public immutable lpToken;

    uint256 public pendingExchangeRate;
    uint256 public pendingExchangeRateBlock;

    /// @notice Price of the LP token in terms of underlying: `exchangeRate * LP = underlying`
    uint256 public exchangeRate;

    modifier onlyAdmin() {
        require(_admins.contains(msg.sender), "ConicLpTokenOracle: forbidden");
        _;
    }

    constructor(IConicPool _conicPool) {
        conicPool = _conicPool;
        lpToken = _conicPool.lpToken();
        exchangeRate = _conicPool.exchangeRate();
        _admins.add(msg.sender);
    }

    function requestExchangeRateUpdate() external onlyAdmin {
        uint256 currentExchangeRate = conicPool.exchangeRate();
        pendingExchangeRate = currentExchangeRate;
        pendingExchangeRateBlock = block.number;
        emit ExchangeRateUpdateRequested(currentExchangeRate);
    }

    function executeExchangeRateUpdate() external onlyAdmin {
        require(
            pendingExchangeRateBlock > 0,
            "ConicLpTokenOracle: no pending exchange rate update"
        );
        require(
            block.number > pendingExchangeRateBlock,
            "ConicLpTokenOracle: cannot execute rate update"
        );
        uint256 oldExchangeRate = exchangeRate;
        uint256 newExchangeRate = pendingExchangeRate;
        exchangeRate = newExchangeRate;
        pendingExchangeRate = 0;
        pendingExchangeRateBlock = 0;
        emit ExchangeRateUpdateExecuted(oldExchangeRate, newExchangeRate);
    }

    function addAdmin(address admin) external onlyAdmin {
        if (_admins.add(admin)) emit AdminAdded(admin);
    }

    function removeAdmin(address admin) external onlyAdmin {
        require(_admins.length() > 1, "ConicLpTokenOracle: cannot remove last admin");
        if (_admins.remove(admin)) emit AdminRemoved(admin);
    }

    function listAdmins() external view returns (address[] memory admins) {
        return _admins.values();
    }
}
