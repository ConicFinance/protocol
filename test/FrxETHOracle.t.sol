// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicTest.sol";

import "../contracts/oracles/FrxETHOracle.sol";

contract FrxETHOracleTest is ConicTest {
    FrxETHPriceOracle oracle;

    function setUp() public override {
        super.setUp();
        _setFork(mainnetFork);
        oracle = new FrxETHPriceOracle();
    }

    function testIsTokenSupported() public {
        assertTrue(oracle.isTokenSupported(Tokens.FRXETH));
        assertFalse(oracle.isTokenSupported(address(0)));
        assertFalse(oracle.isTokenSupported(Tokens.CBETH));
    }

    function testGetUSDPrice() public {
        vm.expectRevert("only supports FRXETH");
        oracle.getUSDPrice(Tokens.CBETH);

        ChainlinkOracle chainlinkOracle = new ChainlinkOracle();
        uint256 frxETHPrice = oracle.getUSDPrice(Tokens.FRXETH);
        uint256 ethPrice = chainlinkOracle.getUSDPrice(Tokens.ETH);
        assertApproxEqRel(frxETHPrice, ethPrice, 0.01e18);
        assertGt(frxETHPrice, 1_000e18);
        assertLt(frxETHPrice, 5_000e18);
    }
}
