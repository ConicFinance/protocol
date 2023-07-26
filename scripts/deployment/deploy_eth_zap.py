from brownie import EthZap, ConicEthPool
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    return load_deployer_account().deploy(EthZap, ConicEthPool[0], gas_price=GAS_PRICE)
