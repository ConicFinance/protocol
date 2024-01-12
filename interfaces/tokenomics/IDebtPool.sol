// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

interface IDebtPool {
    event DebtTokenRedeemed(
        address indexed account,
        uint256 debtTokenAmount,
        uint256 crvAmount,
        uint256 cvxAmount,
        uint256 cncAmount
    );

    function redeemDebtToken(uint256 debtTokenAmount) external;

    function redeemable(
        uint256 debtTokenAmount
    ) external view returns (uint256 crvAmount, uint256 cvxAmount, uint256 cncAmount);

    function exchangeRate()
        external
        view
        returns (uint256 crvPerDebtToken, uint256 cvxPerDebtToken, uint256 cncPerDebtToken);
}
