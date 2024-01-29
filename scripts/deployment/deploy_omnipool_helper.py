from brownie import OmnipoolHelper
from support.constants import GAS_PRICE  # type: ignore
from support.utils import get_mainnet_address, load_deployer_account


def main():
    deployer = load_deployer_account()
    controller = get_mainnet_address("Controller")
    deployer.deploy(OmnipoolHelper, controller, gas_price=GAS_PRICE)
