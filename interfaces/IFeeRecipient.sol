// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IFeeRecipient {
    event FeesReceived(address indexed sender, uint256 crvAmount, uint256 cvxAmount);

    function receiveFees(uint256 amountCrv, uint256 amountCvx) external;
}
