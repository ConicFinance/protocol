// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicPoolBaseTest.sol";
import "../interfaces/vendor/IBooster.sol";
import "../interfaces/vendor/IBaseRewardPool.sol";
import "../interfaces/pools/IRewardManager.sol";

import "../contracts/ConvexHandler.sol";
import "../contracts/testing/MockBonding.sol";

interface CVXMinter {
    function mint(address to, uint256 amount) external;
}

contract RewardManagerV2Test is ConicPoolBaseTest {
    using ScaledMath for uint256;

    IConicPool public conicPool;
    IERC20Metadata public underlying;
    uint256 public decimals;
    IRewardManager public rewardManager;
    IConvexHandler public convexHandler;
    ICurveHandler public curveHandler;

    ICurvePoolV2 public constant CNC_ETH_POOL =
        ICurvePoolV2(0x838af967537350D2C44ABB8c010E49E32673ab94);
    address public constant GOVERNANCE_PROXY = address(0xCb7c67bDde9F7aF0667E8d82bb87F1432Bd1d902);
    uint256 public DEPOSIT_AMOUNT;
    uint256 public CLIFFS_REMAINING = 7;

    function setUp() public override {
        super.setUp();
        underlying = IERC20Metadata(Tokens.DAI);
        decimals = underlying.decimals();
        setTokenBalance(bb8, address(underlying), 100_000 * 10 ** decimals);
        conicPool = _createConicPool(
            controller,
            rewardsHandler,
            address(underlying),
            "Conic DAI",
            "cncDAI",
            false
        );

        controller.setAllowedMultipleDepositsWithdraws(bb8, true);

        rewardManager = conicPool.rewardManager();

        curveHandler = ICurveHandler(controller.curveHandler());
        convexHandler = IConvexHandler(controller.convexHandler());

        conicPool.addPool(CurvePools.TRI_POOL);

        IConicPool.PoolWeight[] memory weights = new IConicPool.PoolWeight[](1);
        weights[0] = IConicPool.PoolWeight(CurvePools.TRI_POOL, 1e18);
        _setWeights(address(conicPool), weights);

        IBonding bonding = new MockBonding();
        controller.setBonding(address(bonding));

        DEPOSIT_AMOUNT = 10_000 * 10 ** decimals;
    }

    function testInitialState() public {
        assertEq(address(conicPool.controller()), address(controller));
        assertEq(conicPool.lpToken().name(), "Conic DAI");
        assertEq(conicPool.lpToken().symbol(), "cncDAI");
        assertEq(address(conicPool.underlying()), address(underlying));
        assertFalse(conicPool.isShutdown());
        assertFalse(conicPool.rebalancingRewardActive());
        assertEq(conicPool.depegThreshold(), 0.03e18);
        assertEq(conicPool.maxIdleCurveLpRatio(), 0.05e18);
    }

    function testHasNoRewardsAtStart() external {
        (uint256 cnc, uint256 crv, uint256 cvx) = rewardManager.claimableRewards(bb8);
        assertEq(cnc, 0);
        assertEq(crv, 0);
        assertEq(cvx, 0);
    }

    function testClaimRewards() external {
        _deposit();

        vm.warp(block.timestamp + 86400);

        _testPositiveClaim();
    }

    function testExtraRewardTokens() external {
        rewardManager.addExtraReward(Tokens.SUSHI);

        _deposit();

        vm.warp(block.timestamp + 86400);

        // simulate reward token
        setTokenBalance(address(this), Tokens.SUSHI, 10_0000e18);
        IERC20(Tokens.SUSHI).transfer(address(conicPool), 1000e18);
        uint256 uniPrice = controller.priceOracle().getUSDPrice(Tokens.SUSHI);
        uint256 ethPrice = controller.priceOracle().getUSDPrice(Tokens.ETH);
        uint256 cncEthPrice = CNC_ETH_POOL.get_dy(0, 1, 1e18);
        uint256 expectedCncAmount = ((1000e18 * uniPrice) / ethPrice).mulDown(cncEthPrice);

        assertTrue(lpTokenStaker.getBalanceForPool(address(conicPool)) > 0);

        IBooster(controller.convexBooster()).earmarkRewards(ConvexPid.TRI_POOL);
        assertTrue(convexHandler.getCrvEarnedBatch(address(conicPool), conicPool.allPools()) > 0);
        (uint256 cncBalance, , ) = rewardManager.claimableRewards(bb8);
        assertTrue(cncBalance > 0);

        uint256 cncBefore = IERC20(Tokens.CNC).balanceOf(bb8);

        vm.prank(bb8);
        rewardManager.claimEarnings();
        uint256 cncEarned = IERC20(Tokens.CNC).balanceOf(bb8) - cncBefore;

        assertApproxEqRel(cncEarned, cncBalance + expectedCncAmount, 0.02e18);

        vm.warp(block.timestamp + 86400);
        IERC20(Tokens.SUSHI).transfer(address(conicPool), 1000e18);
        (cncBalance, , ) = rewardManager.claimableRewards(bb8);
        rewardManager.claimPoolEarningsAndSellRewardTokens();
        rewardManager.poolCheckpoint();
        assertTrue(cncBalance > 0);

        cncBefore = IERC20(Tokens.CNC).balanceOf(bb8);

        vm.prank(bb8);
        rewardManager.claimEarnings();
        cncEarned = IERC20(Tokens.CNC).balanceOf(bb8) - cncBefore;

        assertApproxEqRel(cncEarned, cncBalance + expectedCncAmount, 0.02e18);
        assertApproxEqAbs(IERC20(Tokens.CNC).balanceOf(address(conicPool)), 0, 1e10);
    }

    function testClaimRewardsAfterUnstake() external {
        _deposit();

        vm.warp(block.timestamp + 86400);
        assertTrue(lpTokenStaker.getBalanceForPool(address(conicPool)) > 0);

        IBooster(controller.convexBooster()).earmarkRewards(ConvexPid.TRI_POOL);
        assertTrue(convexHandler.getCrvEarnedBatch(address(conicPool), conicPool.allPools()) > 0);
        uint256 lpTokensBalance = lpTokenStaker.getUserBalanceForPool(address(conicPool), bb8);
        vm.prank(bb8);
        conicPool.unstakeAndWithdraw(lpTokensBalance, 0);

        _testPositiveClaim();
    }

    function testRewardHandlingIfClaimedOnConvex() external {
        _deposit();

        vm.warp(block.timestamp + 86400);
        rewardManager.poolCheckpoint();

        (uint256 cncEarned, uint256 crvEarned, uint256 cvxEarned) = rewardManager.claimableRewards(
            bb8
        );
        assertTrue(cncEarned > 0);
        assertTrue(crvEarned > 0);
        assertTrue(cvxEarned > 0);

        uint256 cncIdleBalance = IERC20(Tokens.CNC).balanceOf(address(conicPool));
        uint256 crvIdleBalance = IERC20(Tokens.CRV).balanceOf(address(conicPool));
        uint256 cvxIdleBalance = IERC20(Tokens.CVX).balanceOf(address(conicPool));

        // claim on behalf of Omnipool directly from Convex reward pool
        address rewardPool = controller.curveRegistryCache().getRewardPool(CurvePools.TRI_POOL);
        IBaseRewardPool(rewardPool).getReward(address(conicPool), true);

        assertTrue(IERC20(Tokens.CNC).balanceOf(address(conicPool)) == cncIdleBalance);
        assertTrue(IERC20(Tokens.CRV).balanceOf(address(conicPool)) > crvIdleBalance);
        assertTrue(IERC20(Tokens.CVX).balanceOf(address(conicPool)) > cvxIdleBalance);

        (
            uint256 cncEarnedPostClaim,
            uint256 crvEarnedPostClaim,
            uint256 cvxEarnedPostClaim
        ) = rewardManager.claimableRewards(bb8);
        assertEq(cncEarned, cncEarnedPostClaim);
        assertEq(crvEarned, crvEarnedPostClaim);
        assertEq(cvxEarned, cvxEarnedPostClaim);

        vm.warp(block.timestamp + 86400);
        IBaseRewardPool(rewardPool).getReward(address(conicPool), true);

        (cncEarned, crvEarned, cvxEarned) = rewardManager.claimableRewards(bb8);

        assertTrue(cncEarned > cncEarnedPostClaim);
        assertTrue(crvEarned > crvEarnedPostClaim);
        assertTrue(cvxEarned > cvxEarnedPostClaim);

        vm.prank(bb8);
        rewardManager.claimEarnings();

        (cncEarnedPostClaim, crvEarnedPostClaim, cvxEarnedPostClaim) = rewardManager
            .claimableRewards(bb8);
        assertEq(cncEarnedPostClaim, 0);
        assertEq(crvEarnedPostClaim, 0);
        assertEq(cvxEarnedPostClaim, 0);

        assertEq(IERC20(Tokens.CNC).balanceOf(bb8), cncEarned);
        assertEq(IERC20(Tokens.CRV).balanceOf(bb8), crvEarned);
        assertEq(IERC20(Tokens.CVX).balanceOf(bb8), cvxEarned);
    }

    function testClaimEarnings() external {
        _deposit(10);

        uint256 ITERATIONS = 365;
        uint256 initialRate = inflationManager.currentInflationRate();
        for (uint256 i = 0; i < ITERATIONS; i++) {
            vm.prank(bb8);
            rewardManager.claimEarnings();
            _deposit(10);
            vm.warp(block.timestamp + 86400);
        }
        uint256 currentRate = inflationManager.currentInflationRate();
        assertEq(currentRate, initialRate);

        rewardManager.poolCheckpoint();

        vm.prank(bb8);
        rewardManager.claimEarnings();
        vm.prank(bb8);
        rewardManager.claimEarnings();

        (uint256 cncEarned, uint256 crvEarned, uint256 cvxEarned) = rewardManager.claimableRewards(
            bb8
        );
        assertTrue(cncEarned == 0);
        assertTrue(crvEarned == 0);
        assertTrue(cvxEarned == 0);
    }

    function _advanceCVXCliff() internal {
        uint256 totalCliffs = 1000;
        uint256 reductionPerCliff = 100000000000000000000000;
        uint256 totalSupply = IERC20(Tokens.CVX).totalSupply();
        uint256 currentCliff = totalSupply / (reductionPerCliff);

        uint256 cliffsLeft = totalCliffs - currentCliff;
        uint256 cvxNeededUntilNextCliff = 100_000e18 - (totalSupply % 100_000e18);
        uint256 crvNeededUntilNextCliff = ((cvxNeededUntilNextCliff /
            ((cliffsLeft * 1e18) / totalCliffs)) * 1e18);

        vm.prank(address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31));
        CVXMinter(Tokens.CVX).mint(Tokens.CVX, crvNeededUntilNextCliff + 1e18); // add 1 extra CVX to avoid imprecisions
        // mint to CVX contract so that no account balances are manipulated

        currentCliff = (IERC20(Tokens.CVX).totalSupply()) / (reductionPerCliff);

        cliffsLeft = totalCliffs - currentCliff;
        totalSupply = IERC20(Tokens.CVX).totalSupply();

        cvxNeededUntilNextCliff = 100_000e18 - (totalSupply % 100_000e18);
        currentCliff = totalSupply / (reductionPerCliff);
        crvNeededUntilNextCliff = ((cvxNeededUntilNextCliff / ((cliffsLeft * 1e18) / totalCliffs)) *
            1e18);
    }

    function _advanceCVXSupplyToBeWithinThreshold(uint256 cliffThreshold) internal {
        uint256 totalCliffs = 1000;
        uint256 reductionPerCliff = 100000000000000000000000; // 100_000 CVX
        uint256 totalSupply = IERC20(Tokens.CVX).totalSupply();
        uint256 currentCliff = totalSupply / (reductionPerCliff);
        uint256 cliffsLeft = totalCliffs - currentCliff;

        uint256 requiredThresholdAmount = (reductionPerCliff * cliffThreshold) / 1e18;
        uint256 cvxNeededUntilNextCliff = reductionPerCliff - (totalSupply % reductionPerCliff);
        if (cvxNeededUntilNextCliff <= requiredThresholdAmount) return;

        uint256 amountNeeded = cvxNeededUntilNextCliff - requiredThresholdAmount + 1e18;
        uint256 crvNeededUntilNextCliff = ((amountNeeded / ((cliffsLeft * 1e18) / totalCliffs)) *
            1e18);

        vm.prank(address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31));
        CVXMinter(Tokens.CVX).mint(Tokens.CVX, crvNeededUntilNextCliff);

        totalSupply = IERC20(Tokens.CVX).totalSupply();
        cvxNeededUntilNextCliff = reductionPerCliff - (totalSupply % reductionPerCliff);
        assertTrue(cvxNeededUntilNextCliff <= requiredThresholdAmount);
        currentCliff = totalSupply / (reductionPerCliff);
    }

    function testCVXCliffChange() external {
        uint256 reductionPerCliff = 100000000000000000000000;
        uint256 totalSupply = IERC20(Tokens.CVX).totalSupply();
        uint256 oldCliff = totalSupply / (reductionPerCliff);

        _advanceCVXCliff();

        totalSupply = IERC20(Tokens.CVX).totalSupply();
        uint256 currentCliff = totalSupply / (reductionPerCliff);

        assertTrue(currentCliff > oldCliff);
    }

    function _testClaimEarningsWithNewCVXCliff() internal {
        _advanceCVXCliff();
        setTokenBalance(bb8, Tokens.DAI, DEPOSIT_AMOUNT);
        _deposit();

        vm.warp(block.timestamp + 86400);

        uint256 CLIFF_THRESHOLD = 0.04e18; // can be set in ConvexHandler

        vm.prank(GOVERNANCE_PROXY);
        _advanceCVXSupplyToBeWithinThreshold(CLIFF_THRESHOLD);
        rewardManager.poolCheckpoint();

        vm.warp(block.timestamp + 40000);

        _advanceCVXCliff();

        vm.prank(bb8);
        rewardManager.claimEarnings();

        vm.warp(block.timestamp + 30000);

        vm.prank(bb8);
        rewardManager.claimEarnings();
    }

    function testSetFeePercentage() external {
        controller.setFeeRecipient(address(locker));
        setTokenBalance(r2, Tokens.CNC, 100_000e18);
        vm.prank(r2);
        IERC20(Tokens.CNC).approve(address(locker), 100_000e18);
        vm.prank(r2);
        locker.lock(10e18, 160 days);
        rewardManager.setFeePercentage(0.01e18);

        assertTrue(rewardManager.feesEnabled());
        assertEq(rewardManager.feePercentage(), 0.01e18);

        vm.expectRevert("must be different to current");
        rewardManager.setFeePercentage(0.01e18);

        rewardManager.setFeePercentage(0.05e18);
        assertTrue(rewardManager.feesEnabled());
        assertEq(rewardManager.feePercentage(), 0.05e18);

        rewardManager.setFeePercentage(0);
        assertFalse(rewardManager.feesEnabled());
        assertEq(rewardManager.feePercentage(), 0);
    }

    function testClaimRewardsWithFees() external {
        controller.setFeeRecipient(address(locker));
        setTokenBalance(r2, Tokens.CNC, 100_000e18);
        vm.prank(r2);
        IERC20(Tokens.CNC).approve(address(locker), 100_000e18);
        vm.prank(r2);
        locker.lock(10e18, 160 days);
        rewardManager.setFeePercentage(0.01e18);

        assertTrue(rewardManager.feesEnabled());

        _deposit();

        vm.warp(block.timestamp + 86400);

        _testPositiveClaim();
    }

    function testClaimEarningsWithNewCVXCliff() external {
        _testClaimEarningsWithNewCVXCliff();
    }

    function testFailClaimEarningsWithNewCVXCliffV2Handler() external {
        vm.prank(controller.owner());
        controller.setConvexHandler(address(new ConvexHandler(address(controller))));
        vm.expectRevert();
        _testClaimEarningsWithNewCVXCliff();
    }

    function testNoConvexRewards() external {
        _deposit();

        vm.warp(block.timestamp + 86400);
        _testPositiveClaim();

        for (uint256 i; i < CLIFFS_REMAINING - 1; i++) {
            _advanceCVXCliff();
            vm.warp(block.timestamp + 86400);
            _testPositiveClaim();
        }

        _advanceCVXCliff();
        vm.warp(block.timestamp + 86400);
        _testZeroClaim();
    }

    function _deposit() internal {
        _deposit(DEPOSIT_AMOUNT / (10 ** underlying.decimals()));
    }

    function _deposit(uint256 unscaledAmount) internal {
        uint256 amount = unscaledAmount * 10 ** underlying.decimals();
        vm.prank(bb8);
        underlying.approve(address(conicPool), amount);
        vm.prank(bb8);
        conicPool.deposit(amount, 0);

        inflationManager.updatePoolWeights();
        IBooster(controller.convexBooster()).earmarkRewards(ConvexPid.TRI_POOL);
    }

    function _testPositiveClaim() internal {
        assertGt(convexHandler.getCrvEarnedBatch(address(conicPool), conicPool.allPools()), 0);
        (uint256 cncBalance, uint256 crvBalance, uint256 cvxBalance) = rewardManager
            .claimableRewards(bb8);
        assertGt(cncBalance, 0, "CNC balance should be greater than 0");
        assertGt(crvBalance, 0, "CRV balance should be greater than 0");
        assertGt(cvxBalance, 0, "CVX balance should be greater than 0");

        uint256 CRV_BEFORE = IERC20(Tokens.CRV).balanceOf(bb8);
        uint256 CVX_BEFORE = IERC20(Tokens.CVX).balanceOf(bb8);
        uint256 CNC_BEFORE = IERC20(Tokens.CNC).balanceOf(bb8);

        vm.prank(bb8);
        rewardManager.claimEarnings();

        assertEq(IERC20(Tokens.CRV).balanceOf(bb8), CRV_BEFORE + crvBalance);
        assertEq(IERC20(Tokens.CVX).balanceOf(bb8), CVX_BEFORE + cvxBalance);
        assertEq(IERC20(Tokens.CNC).balanceOf(bb8), CNC_BEFORE + cncBalance);
    }

    function _testZeroClaim() internal {
        (uint256 cncBalance, uint256 crvBalance, uint256 cvxBalance) = rewardManager
            .claimableRewards(bb8);
        assertGt(cncBalance, 0, "CNC balance should be greater than 0");
        assertEq(cvxBalance, 0, "CVX balance should be 0");

        uint256 CRV_BEFORE = IERC20(Tokens.CRV).balanceOf(bb8);
        uint256 CVX_BEFORE = IERC20(Tokens.CVX).balanceOf(bb8);
        uint256 CNC_BEFORE = IERC20(Tokens.CNC).balanceOf(bb8);

        vm.prank(bb8);
        rewardManager.claimEarnings();

        assertEq(IERC20(Tokens.CRV).balanceOf(bb8), CRV_BEFORE + crvBalance);
        assertEq(IERC20(Tokens.CVX).balanceOf(bb8), CVX_BEFORE + cvxBalance);
        assertEq(IERC20(Tokens.CNC).balanceOf(bb8), CNC_BEFORE + cncBalance);
    }
}
