from brownie import CurveLPOracle, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account


def main():
    deployer = load_deployer_account()
    deployer.deploy(CurveLPOracle, Controller[0], gas_price=GAS_PRICE)
