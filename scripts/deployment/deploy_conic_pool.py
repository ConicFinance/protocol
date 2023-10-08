import json
import os

from brownie import (
    ConicPool,
    interface,
    RewardManager,
)
from brownie.project.main import get_loaded_projects
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account, get_mainnet_address, scale
from support.addresses import *  # type: ignore

MAX_DEVIATION = int(5e16)

POOL = os.environ.get("POOL")


def get_config():
    config_path = (
        get_loaded_projects()[0]._path
        / "scripts"
        / "deployment"
        / "omnipool-config.json"
    )
    with config_path.open() as fp:
        return json.load(fp)[POOL]


def main():
    config = get_config()
    deployer = load_deployer_account()

    controller = get_mainnet_address("Controller")
    inflationManager = get_mainnet_address("InflationManager")
    cncMintingRebalancingRewardsHandler = get_mainnet_address(
        "CNCMintingRebalancingRewardsHandler"
    )
    governance_proxy = get_mainnet_address("GovernanceProxy")
    cnc_locker = get_mainnet_address("CNCLockerV3")

    reward_manager = deployer.deploy(
        RewardManager,
        controller,
        config["underlying"],
        cnc_locker,
        gas_price=GAS_PRICE,
    )

    conic_pool = deployer.deploy(
        ConicPool,
        config["underlying"],
        reward_manager,
        controller,
        config["lpName"],
        config["lpSymbol"],
        CVX,
        CRV,
        gas_price=GAS_PRICE,
    )
    reward_manager.initialize(conic_pool, {"gas_price": GAS_PRICE, "from": deployer})

    conic_pool.setMaxDeviation(
        MAX_DEVIATION, {"gas_price": GAS_PRICE, "from": deployer}
    )

    curve_pools = config["curvePools"]
    for curve_pool in curve_pools:
        conic_pool.addCurvePool(
            curve_pool["address"], {"gas_price": GAS_PRICE, "from": deployer}
        )
    conic_pool.transferOwnership(
        governance_proxy, {"from": deployer, "gas_price": GAS_PRICE}
    )
    reward_manager.transferOwnership(
        governance_proxy, {"from": deployer, "gas_price": GAS_PRICE}
    )

    print("Governance proxy address: ", governance_proxy)
    print("Add pool to controller")
    print("Target contract", controller)
    print(
        "Target data:\n",
        interface.IController(controller).addPool.encode_input(conic_pool),
    )
    print("-" * 80)
    print("Add rebalancing reward handler for pool")
    print("Target contract", inflationManager)
    print(
        "Target data:\n",
        interface.InflationManager(
            inflationManager
        ).addPoolRebalancingRewardHandler.encode_input(
            conic_pool, cncMintingRebalancingRewardsHandler
        ),
    )
    return conic_pool
