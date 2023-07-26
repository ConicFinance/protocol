from brownie import CurveRegistryCache
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from brownie import accounts


def main():
    deployer = load_deployer_account()
    # accounts[1].transfer(deployer, "3 ether")
    curve_registry_cache = deployer.deploy(CurveRegistryCache, gas_price=GAS_PRICE)

    return curve_registry_cache
