from brownie import ConicLpTokenOracle, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import get_mainnet_address, load_deployer_account


def main(conic_pool):
    controller = Controller.at(get_mainnet_address("Controller"))
    assert conic_pool in controller.listPools(), "Conic pool not in controller"

    return load_deployer_account().deploy(
        ConicLpTokenOracle, conic_pool, gas_price=GAS_PRICE
    )
