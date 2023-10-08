// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicPoolBaseTest.sol";
import "../contracts/oracles/ChainlinkOracle.sol";

contract ChainlinkOracleTest is ConicPoolBaseTest {
    ChainlinkOracle public oracle;

    function setUp() public override {
        super.setUp();
        oracle = new ChainlinkOracle();
    }

    function testChainlinkOracle() public {
        assertApproxEqRel(oracle.getUSDPrice(Tokens.ETH), 1_500e18, 1_000e18, "ETH");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.DAI), 1e18, 0.1e18, "DAI");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.WETH), 1_500e18, 1_000e18, "WETH");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.USDT), 1e18, 0.1e18, "USDT");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.CRV), 0.5e18, 2e18, "CRV");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.USDC), 1e18, 0.1e18, "USDC");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.ST_ETH), 1_500e18, 1_000e18, "ST_ETH");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.CVX), 3e18, 2e18, "CVX");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.FRAX), 1e18, 0.1e18, "FRAX");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.CRV_USD), 1e18, 0.1e18, "CRV_USD");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.CBETH), 1_500e18, 1_000e18, "CBETH");
        assertApproxEqRel(oracle.getUSDPrice(Tokens.RETH), 1_500e18, 1_000e18, "RETH");
    }
}
