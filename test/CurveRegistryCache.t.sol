// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicTest.sol";

contract CurveRegistryCacheTest is ConicTest {
    using ArrayExtensions for address[];

    ICurveRegistryCache public registryCache;

    function setUp() public override {
        super.setUp();
        _setFork(mainnetFork);
        registryCache = _createRegistryCache();
    }

    function testIsRegistered() public {
        assertTrue(registryCache.isRegistered(CurvePools.STETH_ETH_POOL));
        assertTrue(registryCache.isRegistered(CurvePools.FRAX_3CRV));
        assertFalse(registryCache.isRegistered(address(0)));
    }

    function testLpToken() public {
        assertEq(registryCache.lpToken(CurvePools.STETH_ETH_POOL), Tokens.STETH_ETH_LP);
        assertEq(registryCache.lpToken(CurvePools.FRAX_3CRV), Tokens.FRAX_3CRV_LP);
    }

    function testHasCoinDirectly() public {
        assertTrue(registryCache.hasCoinDirectly(CurvePools.TRI_POOL, Tokens.DAI));
        assertFalse(registryCache.hasCoinDirectly(CurvePools.FRAX_3CRV, Tokens.DAI));
    }

    function testHasCoinAnywhere() public {
        assertTrue(registryCache.hasCoinAnywhere(CurvePools.TRI_POOL, Tokens.DAI));
        assertTrue(registryCache.hasCoinAnywhere(CurvePools.FRAX_3CRV, Tokens.DAI));
        assertFalse(registryCache.hasCoinAnywhere(CurvePools.FRAX_3CRV, Tokens.CVX));
    }

    function testInterfaceVersion() public {
        assertEq(registryCache.interfaceVersion(CurvePools.SUSD_DAI_USDT_USDC), 0);
        assertEq(registryCache.interfaceVersion(CurvePools.TRI_POOL), 1);
        assertEq(registryCache.interfaceVersion(CurvePools.CNC_ETH), 2);
    }

    function testGetAllUnderlyingCoins() public {
        address[] memory triPoolUnderlying = registryCache.coins(CurvePools.TRI_POOL);
        assertEq(registryCache.getAllUnderlyingCoins(CurvePools.TRI_POOL), triPoolUnderlying);

        address[] memory frax = new address[](1);
        frax[0] = Tokens.FRAX;
        address[] memory frax3CRVUnderlying = frax.concat(triPoolUnderlying);

        assertEq(registryCache.getAllUnderlyingCoins(CurvePools.FRAX_3CRV), frax3CRVUnderlying);
    }
}
