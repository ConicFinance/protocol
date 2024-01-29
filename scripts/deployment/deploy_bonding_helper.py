from brownie import BondingHelper
from support.constants import GAS_PRICE  # type: ignore
from support.utils import get_mainnet_address, load_deployer_account


def main():
    return load_deployer_account().deploy(
        BondingHelper, get_mainnet_address("Bonding"), gas_price=GAS_PRICE
    )
