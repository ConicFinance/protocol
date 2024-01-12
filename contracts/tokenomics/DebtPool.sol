// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../libraries/ScaledMath.sol";

import "../../interfaces/tokenomics/IDebtPool.sol";
import "../../interfaces/IConicDebtToken.sol";
import "../../interfaces/pools/IConicPool.sol";

contract DebtPool is IDebtPool, IFeeRecipient, Ownable {
    using ScaledMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant CNC = IERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);

    IConicDebtToken public debtToken;

    constructor(address _debtToken) {
        debtToken = IConicDebtToken(_debtToken);
    }

    function redeemDebtToken(uint256 debtTokenAmount) external override {
        (uint256 crvAmount, uint256 cvxAmount, uint256 cncAmount) = redeemable(debtTokenAmount);
        debtToken.burn(msg.sender, debtTokenAmount);
        CRV.safeTransfer(msg.sender, crvAmount);
        CVX.safeTransfer(msg.sender, cvxAmount);
        CNC.safeTransfer(msg.sender, cncAmount);

        emit DebtTokenRedeemed(msg.sender, debtTokenAmount, crvAmount, cvxAmount, cncAmount);
    }

    function redeemable(
        uint256 debtTokenAmount
    ) public view override returns (uint256 crvAmount, uint256 cvxAmount, uint256 cncAmount) {
        (
            uint256 crvExchangeRate,
            uint256 cvxExchangeRate,
            uint256 cncExchangeRate
        ) = exchangeRate();
        crvAmount = debtTokenAmount.mulDown(crvExchangeRate);
        cvxAmount = debtTokenAmount.mulDown(cvxExchangeRate);
        cncAmount = debtTokenAmount.mulDown(cncExchangeRate);
    }

    function exchangeRate()
        public
        view
        override
        returns (uint256 crvPerDebtToken, uint256 cvxPerDebtToken, uint256 cncPerDebtToken)
    {
        uint256 debtTokensOutstanding = debtToken.totalSupply();
        crvPerDebtToken = CRV.balanceOf(address(this)).divDown(debtTokensOutstanding);
        cvxPerDebtToken = CVX.balanceOf(address(this)).divDown(debtTokensOutstanding);
        cncPerDebtToken = CNC.balanceOf(address(this)).divDown(debtTokensOutstanding);
    }

    function receiveFees(uint256 amountCrv, uint256 amountCvx) external override {
        CRV.safeTransferFrom(msg.sender, address(this), amountCrv);
        CVX.safeTransferFrom(msg.sender, address(this), amountCvx);
        emit FeesReceived(msg.sender, amountCrv, amountCvx);
    }
}
