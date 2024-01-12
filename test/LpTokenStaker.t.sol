// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicPoolBaseTest.sol";
import "../interfaces/vendor/IBooster.sol";
import "../interfaces/vendor/IBaseRewardPool.sol";
import "../interfaces/pools/IRewardManager.sol";

import "../contracts/ConvexHandler.sol";
import "../contracts/testing/MockBonding.sol";

contract LpTokenStakerTest is ConicPoolBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testIdleCncIsSentToTreasuryWhenShutdown() public {
        uint256 idleAmount = 100e18;
        vm.prank(MainnetAddresses.LP_TOKEN_STAKER);
        cnc.mint(address(lpTokenStaker), idleAmount);

        uint256 treasuryCncBefore = cnc.balanceOf(MainnetAddresses.MULTISIG);
        vm.prank(address(controller));
        lpTokenStaker.shutdown();
        assertEq(
            cnc.balanceOf(MainnetAddresses.MULTISIG),
            treasuryCncBefore + idleAmount,
            "idle cnc not sent to treasury"
        );
        assertEq(cnc.balanceOf(address(lpTokenStaker)), 0, "staker still has cnc");
    }
}
