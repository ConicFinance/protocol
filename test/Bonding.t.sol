// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicTest.sol";
import "./ConicPoolBaseTest.sol";

contract BondingTest is ConicPoolBaseTest {
    Bonding public bonding;
    IConicPool public crvusdPool;
    IERC20Metadata public underlying;
    uint256 public decimals;

    function setUp() public override {
        super.setUp();

        underlying = IERC20Metadata(Tokens.CRV_USD);
        decimals = underlying.decimals();
        setTokenBalance(bb8, address(underlying), 100_000 * 10 ** decimals);
        crvusdPool = _createConicPool(
            controller,
            rewardsHandler,
            locker,
            address(underlying),
            "Conic crvUSD",
            "cncCRVUSD",
            false
        );

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

        cnc = CNCToken(controller.cncToken());
        // Use lp tokenstaker to get minting rights
        vm.prank(MainnetAddresses.LP_TOKEN_STAKER);
        cnc.mint(address(bb8), 104_000e18);
        vm.prank(bb8);
        cnc.transfer(address(bonding), 104_000e18);
        bonding.startBonding();
    }

    function testInitialState() public {
        assertEq(cnc.balanceOf(address(bonding)), 104_000e18);
        assertEq(bonding.totalNumberEpochs(), 52);
        assertEq(bonding.epochDuration(), 7 days);
        assertEq(bonding.cncPerEpoch(), 2_000e18);
    }

    function testCurrentCncBondPriceStart() public {
        assertApproxEqRel(2e18, bonding.computeCurrentCncBondPrice(), 0.01e18);
    }

    function testSingleBond() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        bonding.bondCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

        uint256 cncReceived = cnc.balanceOf(address(locker));
        uint256 crvUsdReceived = lpTokenStaker.getUserBalanceForPool(
            address(crvusdPool),
            address(bonding)
        );
        assertApproxEqRel(cncReceived, 500e18, 0.01e18);
        assertApproxEqRel(crvUsdReceived, 1000e18, 0.01e18);
        assertApproxEqRel(bonding.cncDistributed(), 500e18, 0.01e18);
        assertApproxEqRel(bonding.lastCncPrice(), 2e18, 0.01e18);
        assertApproxEqRel(bonding.cncStartPrice(), 2e18, 0.01e18);
        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );
    }

    function testSingleBondAfterMultipleEpochs() public {
        // bond after 3 epochs
        skip(21 days);
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        uint256 expectedCncReceived = 333e18;
        bonding.bondCrvUsd(1_000 * 10 ** decimals, expectedCncReceived - 5e18, 180 days);

        uint256 cncReceived = cnc.balanceOf(address(locker));
        uint256 crvUsdReceived = lpTokenStaker.getUserBalanceForPool(
            address(crvusdPool),
            address(bonding)
        );

        // The price only gets increased once if multiple epochs are skipped
        assertApproxEqRel(cncReceived, 333e18, 0.01e18);
        assertApproxEqRel(crvUsdReceived, 1000e18, 0.01e18);
        assertApproxEqRel(bonding.cncDistributed(), 333e18, 0.01e18);
        assertApproxEqRel(bonding.lastCncPrice(), 3e18, 0.01e18);
        assertApproxEqRel(bonding.cncStartPrice(), 3e18, 0.01e18);
    }

    function testSingleBondAndCheckpoint() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        bonding.bondCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

        uint256 cncReceived = cnc.balanceOf(address(locker));
        uint256 crvUsdReceived = lpTokenStaker.getUserBalanceForPool(
            address(crvusdPool),
            address(bonding)
        );

        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );

        skip(10.5 days);

        bonding.checkpointAccount(address(bb8));

        assertApproxEqRel(
            500 * 10 ** decimals,
            bonding.perAccountStreamAccrued(address(bb8)),
            0.01e18
        );
        skip(3.5 days);

        bonding.checkpointAccount(address(bb8));
        assertApproxEqRel(
            1_000 * 10 ** decimals,
            bonding.perAccountStreamAccrued(address(bb8)),
            0.01e18
        );

        uint256 balanceBefore = crvusdPool.lpToken().balanceOf(address(bb8));
        bonding.claimStream();

        assertApproxEqRel(
            1_000 * 10 ** decimals,
            crvusdPool.lpToken().balanceOf(address(bb8)) - balanceBefore,
            0.01e18
        );
    }
}
