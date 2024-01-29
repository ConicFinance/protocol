// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../tokenomics/Bonding.sol";

import "../../libraries/ScaledMath.sol";

interface IBondingHelper {
    function claimableCrvUsd(address account) external returns (uint256);
}

contract BondingHelper is IBondingHelper {
    using ScaledMath for uint256;

    Bonding internal immutable bonding;

    constructor(address bondingAddress_) {
        bonding = Bonding(bondingAddress_);
    }

    function claimableCrvUsd(address account) external view override returns (uint256) {
        if (!bonding.bondingStarted()) return 0;
        uint256 streamed_;
        uint256 streamedInEpoch;
        uint256 lastStreamEpochStartTime_ = bonding.lastStreamEpochStartTime();
        uint256 lastStreamUpdate_ = bonding.lastStreamUpdate();
        uint256 streamIntegral_ = bonding.streamIntegral();
        uint256 amount_ = bonding.perAccountStreamAccrued(account);
        while (
            (block.timestamp >= lastStreamEpochStartTime_ + bonding.epochDuration()) &&
            (lastStreamEpochStartTime_ < bonding.bondingEndTime() + bonding.epochDuration())
        ) {
            streamedInEpoch = (lastStreamEpochStartTime_ +
                bonding.epochDuration() -
                lastStreamUpdate_).divDown(bonding.epochDuration()).mulDown(
                    bonding.assetsInEpoch(lastStreamEpochStartTime_)
                );
            lastStreamEpochStartTime_ += bonding.epochDuration();
            lastStreamUpdate_ = lastStreamEpochStartTime_;
            streamed_ += streamedInEpoch;
        }
        streamed_ += (block.timestamp - lastStreamUpdate_).divDown(bonding.epochDuration()).mulDown(
            bonding.assetsInEpoch(lastStreamEpochStartTime_)
        );
        lastStreamUpdate_ = block.timestamp;
        uint256 totalBoosted = bonding.cncLocker().totalBoosted();
        if (totalBoosted > 0) {
            streamIntegral_ += streamed_.divDown(totalBoosted);
        }
        uint256 accountBoostedBalance = bonding.cncLocker().totalStreamBoost(account);
        amount_ += accountBoostedBalance.mulDown(
            streamIntegral_ - bonding.perAccountStreamIntegral(account)
        );
        return amount_;
    }
}
