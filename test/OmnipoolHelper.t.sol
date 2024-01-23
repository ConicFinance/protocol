// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../contracts/helpers/OmnipoolHelper.sol";
import "./ConicPoolBaseTest.sol";

contract OmnipoolHelperTest is ConicPoolBaseTest {
    OmnipoolHelper helper;
    IConicPool public conicPool;
    IERC20Metadata public underlying;
    uint256 public decimals;

    function setUp() public override {
        super.setUp();

        // Setting up the pool
        underlying = IERC20Metadata(Tokens.CRV_USD);
        decimals = underlying.decimals();
        setTokenBalance(bb8, address(underlying), 100_000 * 10 ** decimals);
        conicPool = _createConicPool(
            controller,
            rewardsHandler,
            address(underlying),
            "Conic crvUSD",
            "cncCRVUSD",
            false
        );

        controller.setAllowedMultipleDepositsWithdraws(bb8, true);

        conicPool.addPool(CurvePools.CRVUSD_USDT);
        conicPool.addPool(CurvePools.CRVUSD_USDC);
        IConicPool.PoolWeight[] memory weights = new IConicPool.PoolWeight[](2);
        weights[0] = IConicPoolWeightManagement.PoolWeight(CurvePools.CRVUSD_USDT, 0.6e18);
        weights[1] = IConicPoolWeightManagement.PoolWeight(CurvePools.CRVUSD_USDC, 0.4e18);
        _setWeights(address(conicPool), weights);

        // Setting up the helper
        helper = new OmnipoolHelper(address(controller));
    }

    function testOmnipools() public {
        IOmnipoolHelper.OmnipoolInfo[] memory omnipools = helper.omnipools();

        // Check that the omnipool info is correct
        assertEq(omnipools.length, 1);
        IOmnipoolHelper.OmnipoolInfo memory omnipool = omnipools[0];
        assertEq(omnipool.addr, address(conicPool), "Wrong pool address");
        assertEq(omnipool.underlying.addr, address(underlying), "Wrong underlying address");
        assertEq(omnipool.underlying.name, "Curve.Fi USD Stablecoin", "Wrong underlying name");
        assertEq(omnipool.underlying.symbol, "crvUSD", "Wrong underlying symbol");
        assertEq(omnipool.underlying.decimals, decimals, "Wrong underlying decimals");
        assertEq(omnipool.lpToken.addr, address(conicPool.lpToken()), "Wrong lpToken address");
        assertEq(omnipool.lpToken.name, "Conic crvUSD", "Wrong lpToken name");
        assertEq(omnipool.lpToken.symbol, "cncCRVUSD", "Wrong lpToken symbol");
        assertEq(omnipool.lpToken.decimals, decimals, "Wrong lpToken decimals");
        assertEq(omnipool.exchangeRate, 1e18, "Wrong exchange rate");
        assertEq(omnipool.lams.length, 2, "Wrong number of LAMs");
        assertEq(omnipool.lams[0].addr, CurvePools.CRVUSD_USDT, "Wrong LAM address");
        assertEq(omnipool.lams[0].target, 0.6e18, "Wrong LAM target");
        assertEq(omnipool.lams[0].allocated, 0, "Wrong LAM allocated");
        assertEq(omnipool.lams[1].addr, CurvePools.CRVUSD_USDC, "Wrong LAM address");
        assertEq(omnipool.lams[1].target, 0.4e18, "Wrong LAM target");
        assertEq(omnipool.lams[1].allocated, 0, "Wrong LAM allocated");
        assertEq(omnipool.rebalancingRewardActive, false, "Wrong rebalancing reward active");
        assertEq(omnipool.totalUnderlying, 0, "Wrong total underlying");
        assertEq(omnipool.rewardManager, address(conicPool.rewardManager()), "reward manager");
    }
}
