from brownie import DerivativeOracle, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account


def main():
    return load_deployer_account().deploy(
        DerivativeOracle, Controller[0], gas_price=GAS_PRICE
    )
