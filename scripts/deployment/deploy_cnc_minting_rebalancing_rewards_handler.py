import json

from brownie import (
    CNCMintingRebalancingRewardsHandler,  # type: ignore
    Controller,  # type: ignore
    InflationManager,  # type: ignore
    GovernanceProxy,  # type: ignore
)
from support.constants import GAS_PRICE, LAST_REBALANCING_REWARD_HANDLER_ADDRESS
from support.utils import load_deployer_account
from support.addresses import CNC


def main():
    deployer = load_deployer_account()
    cnc_minting_rebalancing_rewards_handler = deployer.deploy(
        CNCMintingRebalancingRewardsHandler,
        Controller[0],
        CNC,
        LAST_REBALANCING_REWARD_HANDLER_ADDRESS,
        gas_price=GAS_PRICE,
    )
    # cnc_minting_rebalancing_rewards_handler.transferOwnership(
    #     GovernanceProxy[0], {"from": deployer, "gas_price": GAS_PRICE}
    # )


def generate_upgrade_governance_call(old_reward_handler, new_reward_handler):
    calls = []

    inflation_manager = InflationManager[0]
    controller = Controller[0]

    pools = controller.listPools()

    for pool in pools:
        calls.append(
            (
                inflation_manager.address,
                inflation_manager.removePoolRebalancingRewardHandler.encode_input(
                    pool, old_reward_handler
                ),
            )
        )

    calls.append(
        (new_reward_handler.address, new_reward_handler.initialize.encode_input())
    )

    for pool in pools:
        calls.append(
            (
                inflation_manager.address,
                inflation_manager.addPoolRebalancingRewardHandler.encode_input(
                    pool, new_reward_handler
                ),
            )
        )
    return calls


# def generate_v3_upgrade_governance_call():
#     old_reward_handler = CNCMintingRebalancingRewardsHandlerV2[0]
#     new_reward_handler = CNCMintingRebalancingRewardsHandlerV3[0]
#     calls = generate_upgrade_governance_call(old_reward_handler, new_reward_handler)
#     calls.append(
#         (
#             old_reward_handler.address,
#             old_reward_handler.switchMintingRebalancingRewardsHandler.encode_input(
#                 new_reward_handler
#             ),
#         )
#     )

#     print(json.dumps(calls))
