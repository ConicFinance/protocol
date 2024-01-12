// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicTest.sol";
import "./ConicPoolBaseTest.sol";

import "../interfaces/IConicDebtToken.sol";
import "../contracts/testing/MockConicDebtToken.sol";
import "../interfaces/tokenomics/IDebtPool.sol";
import "../contracts/tokenomics/DebtPool.sol";

contract DebtPoolTest is ConicPoolBaseTest {
    Bonding public bonding;
    IConicPool public crvusdPool;
    IERC20Metadata public underlying;
    MockConicDebtToken public debtToken;
    DebtPool public debtPool;
    uint256 public decimals;

    bytes32 constant MERKLE_ROOT_DEBT_TOKEN =
        0x5b09a6971fd93f3daecfe326ce01299059ec999160f4e731d964129accadbe9c;
    bytes32 constant MERKLE_ROOT_REFUND =
        0x332bbf7febd73292fc00b2a4beb458bde392a68bc8f7afa6fa5ad8c77bff8079;

    function setUp() public override {
        super.setUp();

        underlying = IERC20Metadata(Tokens.CRV_USD);
        decimals = underlying.decimals();
        crvusdPool = _createConicPool(
            controller,
            rewardsHandler,
            address(underlying),
            "Conic crvUSD",
            "cncCRVUSD",
            false
        );

        setTokenBalance(bb8, address(underlying), 100_000 * 10 ** decimals);
        controller.setAllowedMultipleDepositsWithdraws(bb8, true);

        // crvUsd pool setup
        crvusdPool.addPool(CurvePools.CRVUSD_USDT);
        crvusdPool.addPool(CurvePools.CRVUSD_USDC);
        IConicPool.PoolWeight[] memory weights = new IConicPool.PoolWeight[](2);
        weights[0] = IConicPool.PoolWeight(CurvePools.CRVUSD_USDT, 0.6e18);
        weights[1] = IConicPool.PoolWeight(CurvePools.CRVUSD_USDC, 0.4e18);
        _setWeights(address(crvusdPool), weights);

        bonding = _createBonding(locker, controller, crvusdPool, 7 days, 52);
        bonding.setCncStartPrice(2e18);
        bonding.setCncPriceIncreaseFactor(1.5e18);
        controller.setBonding(address(bonding));

        debtToken = new MockConicDebtToken(MERKLE_ROOT_DEBT_TOKEN, MERKLE_ROOT_REFUND);
        debtPool = _createDebtPool(address(debtToken));
        debtToken.setDebtPool(address(debtPool));
        bonding.setDebtPool(address(debtPool));

        cnc = CNCToken(controller.cncToken());
        // Use lp tokenstaker to get minting rights
        vm.prank(MainnetAddresses.LP_TOKEN_STAKER);
        cnc.mint(address(bb8), 104_000e18);
        vm.prank(bb8);
        cnc.transfer(address(bonding), 104_000e18);
        bonding.startBonding();

        debtToken.start();
        debtToken.mint(address(bb8), 1_000e18);
    }

    function testInitialState() public {
        assertEq(address(bonding.debtPool()), address(debtPool));
        assertEq(address(debtToken.debtPool()), address(debtPool));
        assertEq(address(debtPool.debtToken()), address(debtToken));
        assertEq(debtToken.totalSupply(), 1_000 * 10 ** 18);
    }

    function testFeeRedirectionRedeemableAndClaiming() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

        uint256 crvUsdReceived = lpTokenStaker.getUserBalanceForPool(
            address(crvusdPool),
            address(bonding)
        );

        assertEq(crvUsdReceived, 1000 * 10 ** decimals);
        assertEq(crvusdPool.lpToken().balanceOf(address(debtPool)), 0);

        skip(30 days);
        bonding.claimFeesForDebtPool();

        (uint256 crvExchangeRate, uint256 cvxExchangeRate, uint256 cncExchangeRate) = debtPool
            .exchangeRate();
        assertGe(crvExchangeRate, 0);
        assertGe(cvxExchangeRate, 0);
        assertGe(cncExchangeRate, 0);

        debtPool.redeemDebtToken(500e18);

        assertGe(IERC20(Tokens.CRV).balanceOf(address(bb8)), 0);
        assertGe(IERC20(Tokens.CVX).balanceOf(address(bb8)), 0);
        assertGe(cnc.balanceOf(address(bb8)), 0);
    }

    function testReceiveFees() public {
        IERC20 crv = IERC20(Tokens.CRV);
        IERC20 cvx = IERC20(Tokens.CVX);

        setTokenBalance(address(this), address(crv), 100e18);
        setTokenBalance(address(this), address(cvx), 100e18);

        crv.approve(address(debtPool), 100e18);
        cvx.approve(address(debtPool), 100e18);

        debtPool.receiveFees(100e18, 100e18);
        assertEq(crv.balanceOf(address(debtPool)), 100e18);
        assertEq(cvx.balanceOf(address(debtPool)), 100e18);
    }
}
