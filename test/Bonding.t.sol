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

        crvusdPool.addPool(CurvePools.CRVUSD_USDT);
        crvusdPool.addPool(CurvePools.CRVUSD_USDC);
        IConicPool.PoolWeight[] memory weights = new IConicPool.PoolWeight[](2);
        weights[0] = IConicPool.PoolWeight(CurvePools.CRVUSD_USDT, 0.6e18);
        weights[1] = IConicPool.PoolWeight(CurvePools.CRVUSD_USDC, 0.4e18);
        _setWeights(address(crvusdPool), weights);

        bonding = _createBonding(locker, controller, crvusdPool, 7 days, 52, 100_000e18);
        bonding.setCncStartPrice(2e18);
        bonding.setCncPriceIncreaseFactor(5e17);
    }

    function testInitialState() public {
        assertEq(cnc.balanceOf(address(bonding)), 0);
    }
}
