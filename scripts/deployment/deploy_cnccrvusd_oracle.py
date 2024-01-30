from brownie import CncCrvUsdOracle
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account


def main():
    return load_deployer_account().deploy(CncCrvUsdOracle, gas_price=GAS_PRICE)
