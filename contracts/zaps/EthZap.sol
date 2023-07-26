// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/pools/IConicPool.sol";
import "../../interfaces/vendor/IWETH.sol";

contract EthZap {
    using Address for address;

    IConicPool public immutable ethPool;
    IWETH internal constant _WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address ethPool_) {
        ethPool = IConicPool(ethPool_);
        _WETH.approve(ethPool_, type(uint256).max);
    }

    function depositFor(
        address account,
        uint256 amount,
        uint256 minLpReceived,
        bool stake
    ) external payable returns (uint256) {
        require(msg.value == amount, "wrong amount");
        _WETH.deposit{value: amount}();
        return ethPool.depositFor(account, amount, minLpReceived, stake);
    }
}
