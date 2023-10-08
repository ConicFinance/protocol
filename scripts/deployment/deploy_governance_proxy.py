from brownie import (
    GovernanceProxy,
    CNCLockerV3,
    CNCMintingRebalancingRewardsHandler,
    ConicPool,
    interface,
    CurveLPOracle,
    DerivativeOracle,
    EmergencyMinter,
    GenericOracle,
    InflationManager,
    Controller,
)
from support.constants import GAS_PRICE, VETO_MULTISIG_ADDRESS  # type: ignore
from support.utils import load_deployer_account


def main():
    deployer = load_deployer_account()
    params = {"from": deployer, "gas_price": GAS_PRICE}
    governance_proxy = deployer.deploy(
        GovernanceProxy, deployer, VETO_MULTISIG_ADDRESS, gas_price=GAS_PRICE
    )
    CNCLockerV3[0].transferOwnership(governance_proxy, params)
    CNCMintingRebalancingRewardsHandler[0].transferOwnership(governance_proxy, params)
    for i in [0, 1, 2]:
        ConicPool[i].transferOwnership(governance_proxy, params)
        reward_manager_address = ConicPool[i].rewardManager()
        reward_manager = interface.IOwnable(reward_manager_address)
        reward_manager.transferOwnership(governance_proxy, params)
    Controller[0].transferOwnership(governance_proxy, params)
    CurveLPOracle[0].transferOwnership(governance_proxy, params)
    EmergencyMinter[0].transferOwnership(governance_proxy, params)
    GenericOracle[0].transferOwnership(governance_proxy, params)
    InflationManager[0].transferOwnership(governance_proxy, params)
    return governance_proxy
