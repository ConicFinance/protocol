from brownie import Controller, CurveRegistryCache
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    deployer = load_deployer_account()
    deployer.deploy(Controller, CNC, CurveRegistryCache[0], gas_price=GAS_PRICE)
