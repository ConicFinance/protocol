// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ConicTest.sol";

contract FakeUnderlying {
    uint8 public decimals = 18;

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }
}

contract FakePool {
    IERC20Metadata public underlying;
    uint64 public rebalancingRewardsActivatedAt;
    uint256 public rebalancingRewardsFactor;

    constructor(address _underlying) {
        underlying = IERC20Metadata(_underlying);
        rebalancingRewardsActivatedAt = uint64(block.timestamp);
        rebalancingRewardsFactor = 1e18;
    }

    function setRewardsActivatedAt(uint64 _rewardsActivatedAt) public {
        rebalancingRewardsActivatedAt = _rewardsActivatedAt;
    }

    function setRebalancingRewardsFactor(uint256 _rebalancingRewardsFactor) public {
        rebalancingRewardsFactor = _rebalancingRewardsFactor;
    }
}

contract CNCMintingRebalancingRewardsHandlerTest is ConicTest {
    FakeUnderlying public underlying;
    FakePool public fakePool;
    Controller public controller;
    CNCMintingRebalancingRewardsHandler public rewardsHandler;

    function setUp() public override {
        super.setUp();
        controller = _createAndInitializeController();
        rewardsHandler = _createRebalancingRewardsHandler(controller);
        underlying = new FakeUnderlying();
        fakePool = new FakePool(address(underlying));
    }

    function testComputeRebalancingRewards() public {
        skip(3600);
        uint256 rebalancingRewards = rewardsHandler.computeRebalancingRewards(
            address(fakePool),
            1000e18,
            500e18
        );
        uint256 expected = 4.16e16; // 500 * 3600 * [5e18 / (3600 * 1 * 10_000 * 6)]
        assertApproxEqRel(rebalancingRewards, expected, 1e16);

        skip(86400 - 3600);
        rebalancingRewards = rewardsHandler.computeRebalancingRewards(
            address(fakePool),
            1000e18,
            500e18
        );
        expected = 1e18; // 500 * 86400 * [5e18 / (3600 * 1 * 10_000 * 6)]
        assertApproxEqRel(rebalancingRewards, expected, 1e16);
    }

    function testMaxElapsedRebalancingRewards() public {
        skip(30 days);
        uint256 rebalancingRewards = rewardsHandler.computeRebalancingRewards(
            address(fakePool),
            1000e18,
            500e18
        );
        // we get 21 days (max) worth of rewards and not 30
        uint256 expected = 2.1e19; // 500 * (21 * 86400) * [5e18 / (3600 * 1 * 10_000 * 6)]
        assertApproxEqRel(rebalancingRewards, expected, 1e16);
    }

    function testComputeRebalancingRewardsDifferentDecimals() public {
        skip(3600);
        underlying.setDecimals(6);
        uint256 rebalancingRewards = rewardsHandler.computeRebalancingRewards(
            address(fakePool),
            1000e6,
            500e6
        );
        uint256 expected = 4.16e16; // 500 * 3600 * [5e18 / (3600 * 1 * 10_000 * 6)]
        assertApproxEqRel(rebalancingRewards, expected, 1e16);
    }

    function testComputeRebalancingRewardsDifferentFactor() public {
        skip(3600);
        fakePool.setRebalancingRewardsFactor(10e18);
        uint256 rebalancingRewards = rewardsHandler.computeRebalancingRewards(
            address(fakePool),
            1000e18,
            500e18
        );
        uint256 expected = 4.16e17; // 500 * 3600 * [5e18 / (3600 * 1 * 10_000 * 6)] * 10
        assertApproxEqRel(rebalancingRewards, expected, 1e16);
    }
}
