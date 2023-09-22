// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../../interfaces/IController.sol";
import "../../interfaces/tokenomics/ICNCLockerV3.sol";
import "../../interfaces/tokenomics/ICNCLockerV3Wrapper.sol";
import "../../libraries/ScaledMath.sol";

contract CNCLockerV3Wrapper is ICNCLockerV3Wrapper {
    using ScaledMath for uint256;

    IController public immutable controller;
    ICNCLockerV3 public immutable locker;

    constructor(IController _controller, ICNCLockerV3 _locker) {
        controller = _controller;
        locker = _locker;
    }

    function balanceOf(address account) external view returns (uint256) {
        return totalVoteBoost(account);
    }

    function totalVoteBoost(address account) public view returns (uint256) {
        return
            locker.totalRewardsBoost(account).mulDown(controller.lpTokenStaker().getBoost(account));
    }
}
