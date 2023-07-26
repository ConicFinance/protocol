from brownie import InflationManager, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    deployer = load_deployer_account()
    inflation_manager = deployer.deploy(
        InflationManager, Controller[0], gas_price=GAS_PRICE
    )
    Controller[0].setInflationManager(
        inflation_manager, {"from": deployer, "gas_price": GAS_PRICE}
    )
    return inflation_manager
