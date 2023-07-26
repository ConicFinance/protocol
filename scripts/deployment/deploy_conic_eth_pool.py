import json

from brownie import ConicEthPool, RewardManager
from brownie.project.main import get_loaded_projects
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account, get_mainnet_address
from support.addresses import *  # type: ignore

MAX_DEVIATION = int(5e16)


def get_config():
    config_path = (
        get_loaded_projects()[0]._path
        / "scripts"
        / "deployment"
        / "omnipool-config.json"
    )
    with config_path.open() as fp:
        return json.load(fp)["eth"]


def main():
    config = get_config()
    deployer = load_deployer_account()
    reward_manager = deployer.deploy(
        RewardManager,
        get_mainnet_address("Controller"),
        config["underlying"],
        get_mainnet_address("CNCLockerV2"),
        gas_price=GAS_PRICE,
    )

    conic_pool = deployer.deploy(
        ConicEthPool,
        config["underlying"],
        reward_manager,
        get_mainnet_address("Controller"),
        config["lpName"],
        config["lpSymbol"],
        CVX,
        CRV,
        gas_price=GAS_PRICE,
    )

    params = {"from": deployer, "gas_price": GAS_PRICE}
    conic_pool.setMaxDeviation(MAX_DEVIATION, params)
    governance_proxy = get_mainnet_address("GovernanceProxy")
    conic_pool.transferOwnership(governance_proxy, params)
    reward_manager.transferOwnership(governance_proxy, params)

    ###
    # All of this we will need to do through the governance proxy from the multisig after deployment
    ###
    # Controller[0].addPool(conic_pool, {"gas_price": GAS_PRICE, "from": deployer})
    # InflationManager[0].addPoolRebalancingRewardHandler(
    #     conic_pool,
    #     CNCMintingRebalancingRewardsHandler[0],
    #     {"gas_price": GAS_PRICE, "from": deployer},
    # )
    # weights = []
    # curve_pools = config["curvePools"]
    # for curve_pool in curve_pools:
    #     conic_pool.addCurvePool(
    #         curve_pool["address"], {"gas_price": GAS_PRICE, "from": deployer}
    #     )
    #     weights.append((curve_pool["address"], Decimal(curve_pool["weight"])*10**18))
    # Controller[0].updateWeights(
    #     (conic_pool, weights), {"gas_price": GAS_PRICE, "from": deployer}
    # )
    return conic_pool
