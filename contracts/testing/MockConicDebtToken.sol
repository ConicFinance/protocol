// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../ConicDebtToken.sol";

contract MockConicDebtToken is ConicDebtToken {
    constructor(
        bytes32 _merkleRootDebtToken,
        bytes32 _merkleRootRefund
    ) ConicDebtToken(_merkleRootDebtToken, _merkleRootRefund) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
