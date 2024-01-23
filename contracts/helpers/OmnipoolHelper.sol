// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../../interfaces/IController.sol";
import "../../interfaces/pools/IConicPool.sol";

interface IOmnipoolHelper {
    struct TokenData {
        address addr;
        string name;
        string symbol;
        uint8 decimals;
    }

    struct LamData {
        address addr;
        uint256 target;
        uint256 allocated;
    }

    struct OmnipoolInfo {
        address addr;
        TokenData underlying;
        TokenData lpToken;
        uint256 exchangeRate;
        LamData[] lams;
        bool rebalancingRewardActive;
        uint256 totalUnderlying;
        address rewardManager;
    }

    function omnipools() external view returns (OmnipoolInfo[] memory);
}

contract OmnipoolHelper is IOmnipoolHelper {
    IController internal immutable controller;

    constructor(address controllerAddress_) {
        controller = IController(controllerAddress_);
    }

    function omnipools() external view override returns (OmnipoolInfo[] memory) {
        address[] memory poolAddresses_ = controller.listPools();

        OmnipoolInfo[] memory omnipools_ = new OmnipoolInfo[](poolAddresses_.length);

        for (uint256 i; i < poolAddresses_.length; i++) {
            IConicPool pool_ = IConicPool(poolAddresses_[i]);

            omnipools_[i] = OmnipoolInfo({
                addr: address(pool_),
                underlying: _getTokenData(pool_.underlying()),
                lpToken: _getTokenData(pool_.lpToken()),
                exchangeRate: pool_.exchangeRate(),
                lams: _getLamData(pool_),
                rebalancingRewardActive: pool_.rebalancingRewardsEnabled(),
                totalUnderlying: pool_.totalUnderlying(),
                rewardManager: address(pool_.rewardManager())
            });
        }

        return omnipools_;
    }

    function _getTokenData(IERC20Metadata token_) internal view returns (TokenData memory) {
        return
            TokenData({
                addr: address(token_),
                name: token_.name(),
                symbol: token_.symbol(),
                decimals: token_.decimals()
            });
    }

    function _getLamData(IConicPool pool_) internal view returns (LamData[] memory) {
        IConicPool.PoolWeight[] memory weights_ = pool_.getWeights();
        IConicPool.PoolWithAmount[] memory allocations_ = pool_.getAllocatedUnderlying();

        LamData[] memory lamData_ = new LamData[](weights_.length);
        for (uint256 i; i < weights_.length; i++) {
            uint256 allocated_;
            for (uint256 j; j < allocations_.length; j++) {
                if (allocations_[j].poolAddress != weights_[i].poolAddress) continue;
                allocated_ = allocations_[j].amount;
                break;
            }

            lamData_[i] = LamData({
                addr: weights_[i].poolAddress,
                target: weights_[i].weight,
                allocated: allocated_
            });
        }

        return lamData_;
    }
}
