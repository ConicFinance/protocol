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
        crvusdPool = _createConicPool(
            controller,
            rewardsHandler,
            address(underlying),
            "Conic crvUSD",
            "cncCRVUSD",
            false
        );

        setTokenBalance(bb8, address(underlying), 100_000 * 10 ** decimals);
        setTokenBalance(c3po, address(underlying), 100_000 * 10 ** decimals);
        controller.setAllowedMultipleDepositsWithdraws(bb8, true);
        controller.setAllowedMultipleDepositsWithdraws(c3po, true);

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

    function testRecovery() public {
        assertEq(cnc.balanceOf(address(bonding)), 104_000e18);
        vm.expectRevert("Bonding has not yet ended");
        bonding.recoverRemainingCNC();
        skip(366 days);
        uint256 balanceBefore = cnc.balanceOf(address(bonding.treasury()));
        bonding.recoverRemainingCNC();
        assertEq(cnc.balanceOf(address(bonding)), 0);
        assertEq(cnc.balanceOf(address(bonding.treasury())) - balanceBefore, 104_000e18);
    }

    function testSingleBond() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

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
        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, expectedCncReceived - 5e18, 180 days);

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

    function testSingleBondAndClaim() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );

        skip(10.5 days);

        bonding.accountCheckpoint(address(bb8));

        assertApproxEqRel(
            500 * 10 ** decimals,
            bonding.perAccountStreamAccrued(address(bb8)),
            0.01e18
        );
        skip(3.5 days);

        bonding.accountCheckpoint(address(bb8));
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

    function testTwoBondsSameEpoch() public {
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        // bond crvusd
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);
        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);
        uint256 cncReceived = cnc.balanceOf(address(locker));
        uint256 crvUsdBalance = lpTokenStaker.getUserBalanceForPool(
            address(crvusdPool),
            address(bonding)
        );
        assertApproxEqRel(cncReceived, 500e18, 0.01e18);
        assertApproxEqRel(crvUsdBalance, 1000e18, 0.01e18);
        assertApproxEqRel(bonding.cncDistributed(), 500e18, 0.01e18);
        assertApproxEqRel(bonding.lastCncPrice(), 2e18, 0.01e18);
        assertApproxEqRel(bonding.cncStartPrice(), 2e18, 0.01e18);
        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );
        vm.stopPrank();
        vm.startPrank(address(c3po));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        // bond crvusd
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);
        bonding.bondCncCrvUsd(500 * 10 ** decimals, 245e18, 180 days);
        cncReceived = cnc.balanceOf(address(locker));
        crvUsdBalance = lpTokenStaker.getUserBalanceForPool(address(crvusdPool), address(bonding));
        assertApproxEqRel(cncReceived, 750e18, 0.01e18);
        assertApproxEqRel(crvUsdBalance, 1500e18, 0.01e18);
        assertApproxEqRel(bonding.cncDistributed(), 750e18, 0.01e18);
        assertApproxEqRel(bonding.lastCncPrice(), 2e18, 0.01e18);
        assertApproxEqRel(bonding.cncStartPrice(), 2e18, 0.01e18);
        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1500e18,
            0.01e18
        );
    }

    function testMultiEpochBondAndClaim() public {
        // set increase factor for easier computation
        bonding.setCncPriceIncreaseFactor(2e18);
        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        vm.stopPrank();
        vm.startPrank(address(c3po));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        // First bonding in epoch 1
        vm.stopPrank();
        vm.startPrank(address(bb8));
        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);
        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );
        skip(10.5 days);

        // Second bonding in epoch 2
        vm.stopPrank();
        vm.startPrank(address(c3po));
        bonding.bondCncCrvUsd(1000 * 10 ** decimals, 240e18, 180 days);
        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );

        skip(10.5 days);

        // Claiming in epoch 4
        vm.stopPrank();
        vm.startPrank(address(bb8));
        uint256 balanceBefore = crvusdPool.lpToken().balanceOf(address(bb8));
        bonding.claimStream();
        assertApproxEqRel(
            1_250 * 10 ** decimals,
            crvusdPool.lpToken().balanceOf(address(bb8)) - balanceBefore,
            0.01e18
        );

        vm.stopPrank();
        vm.startPrank(address(c3po));
        balanceBefore = crvusdPool.lpToken().balanceOf(address(c3po));
        bonding.claimStream();
        assertApproxEqRel(
            750 * 10 ** decimals,
            crvusdPool.lpToken().balanceOf(address(c3po)) - balanceBefore,
            0.01e18
        );
    }

    function testTwoBondAndClaimWithNonBondingLocks() public {
        // get CNC tokens and lock but don't bond
        vm.prank(MainnetAddresses.LP_TOKEN_STAKER);
        cnc.mint(address(c3po), 100_000e18);
        vm.startPrank(c3po);
        cnc.approve(address(locker), 1_000e18);
        locker.lock(1_000e18, 180 days);
        vm.stopPrank();

        // get LP tokens and don't stake
        vm.startPrank(address(bb8));
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        // bond 200o LP tokens for 1000 CNC
        bonding.bondCncCrvUsd(2_000e18, 990e18, 180 days);

        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            2000e18,
            0.01e18
        );

        // skip 2 epochs
        skip(15 days);

        bonding.accountCheckpoint(address(bb8));

        assertApproxEqRel(
            1_000 * 10 ** decimals,
            bonding.perAccountStreamAccrued(address(bb8)),
            0.01e18
        );

        bonding.accountCheckpoint(address(c3po));
        assertApproxEqRel(
            1_000 * 10 ** decimals,
            bonding.perAccountStreamAccrued(address(c3po)),
            0.01e18
        );

        uint256 balanceBefore = crvusdPool.lpToken().balanceOf(address(bb8));
        bonding.claimStream();
        assertApproxEqRel(
            1_000 * 10 ** decimals,
            crvusdPool.lpToken().balanceOf(address(bb8)) - balanceBefore,
            0.01e18
        );
        vm.stopPrank();
        vm.startPrank(c3po);
        balanceBefore = crvusdPool.lpToken().balanceOf(address(c3po));
        bonding.claimStream();
        assertApproxEqRel(
            1_000 * 10 ** decimals,
            crvusdPool.lpToken().balanceOf(address(c3po)) - balanceBefore,
            0.01e18
        );
    }

    function testMinBondingAmount() public {
        bonding.setMinBondingAmount(500e18);

        // get LP tokens and don't stake
        vm.startPrank(address(bb8));
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(10_000 * 10 ** decimals, 1, false);
        uint256 lpReceived = crvusdPool.lpToken().balanceOf(bb8);
        assertApproxEqRel(10_000 * 10 ** decimals, lpReceived, 0.01e18);
        crvusdPool.lpToken().approve(address(bonding), 10_000 * 10 ** decimals);

        vm.expectRevert("Min. bonding amount not reached");
        bonding.bondCncCrvUsd(300 * 10 ** decimals, 290e18, 180 days);
    }

    function testRewardTokensGoToClaimPool() public {
        bonding.setDebtPool(address(c3po));

        vm.startPrank(address(bb8));
        // get LP tokens and don't stake
        underlying.approve(address(crvusdPool), 100_000 * 10 ** decimals);
        crvusdPool.deposit(50_000 * 10 ** decimals, 1, false);
        crvusdPool.lpToken().approve(address(bonding), 50_000 * 10 ** decimals);

        bonding.bondCncCrvUsd(1_000 * 10 ** decimals, 490e18, 180 days);

        assertApproxEqRel(
            bonding.assetsInEpoch(bonding.epochStartTime() + bonding.epochDuration()),
            1000e18,
            0.01e18
        );

        skip(10.5 days);

        bonding.claimFeesForDebtPool();

        assertGt(IERC20(Tokens.CRV).balanceOf(address(c3po)), 0);
        assertGt(IERC20(Tokens.CVX).balanceOf(address(c3po)), 0);
    }
}
