// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicPoolBaseTest.sol";
import "../contracts/oracles/ConicLpTokenOracle.sol";

contract ConicLpTokenOracleTest is ConicPoolBaseTest {
    IConicPool public conicPool;
    ConicLpTokenOracle public conicLpTokenOracle;
    IERC20 public underlying;

    function setUp() public override {
        super.setUp();
        _setFork(mainnetFork);
        conicPool = _createConicPool(
            controller,
            rewardsHandler,
            address(Tokens.CRV_USD),
            "Conic crvUSD",
            "cncCRVUSD",
            false
        );
        underlying = IERC20(Tokens.CRV_USD);
        conicLpTokenOracle = new ConicLpTokenOracle(conicPool);
    }

    function testExchangeRate() public {
        uint256 exchangeRate = conicLpTokenOracle.exchangeRate();
        assertEq(exchangeRate, 1e18, "exchangeRate");
    }

    function testUpdateExchangeRate() public {
        ILpToken lpToken = ILpToken(address(conicPool.lpToken()));
        vm.prank(address(conicPool));
        lpToken.mint(address(this), 100_000 * 10 ** 18, address(this));

        setTokenBalance(bb8, address(underlying), 200_000 * 10 ** 18);
        vm.prank(bb8);
        underlying.transfer(address(conicPool), 200_000 * 10 ** 18);

        vm.prank(r2);
        vm.expectRevert("ConicLpTokenOracle: forbidden");
        conicLpTokenOracle.requestExchangeRateUpdate();

        conicLpTokenOracle.requestExchangeRateUpdate();

        vm.expectRevert("ConicLpTokenOracle: cannot execute rate update");
        conicLpTokenOracle.executeExchangeRateUpdate();

        vm.roll(block.number + 1);
        conicLpTokenOracle.executeExchangeRateUpdate();

        uint256 exchangeRate = conicLpTokenOracle.exchangeRate();
        assertEq(exchangeRate, 2e18, "exchangeRate");

        vm.expectRevert("ConicLpTokenOracle: no pending exchange rate update");
        conicLpTokenOracle.executeExchangeRateUpdate();
    }

    function testAddRemoveAdmins() public {
        vm.prank(r2);
        vm.expectRevert("ConicLpTokenOracle: forbidden");
        conicLpTokenOracle.addAdmin(r2);

        conicLpTokenOracle.addAdmin(r2);
        assertContains(conicLpTokenOracle.listAdmins(), r2);

        vm.prank(r2);
        conicLpTokenOracle.removeAdmin(r2);

        address[] memory admins = conicLpTokenOracle.listAdmins();
        assertEq(admins.length, 1);
        assertEq(admins[0], address(this));

        vm.expectRevert("ConicLpTokenOracle: cannot remove last admin");
        conicLpTokenOracle.removeAdmin(address(this));
    }
}
