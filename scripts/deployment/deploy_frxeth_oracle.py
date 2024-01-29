from brownie import FrxETHPriceOracle, GenericOracle
from support.addresses import FRXETH
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account, get_mainnet_address


def main():
    deployer = load_deployer_account()
    frxeth_oracle = deployer.deploy(FrxETHPriceOracle, gas_price=GAS_PRICE)
    generic_oracle = GenericOracle[0]
    generic_oracle.setCustomOracle(
        FRXETH, frxeth_oracle, {"from": deployer, "gas_price": GAS_PRICE}
    )
