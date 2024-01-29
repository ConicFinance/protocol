from brownie import CurveAdapter, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account, get_mainnet_address


def main():
    deployer = load_deployer_account()
    curve_adapter = deployer.deploy(
        CurveAdapter, get_mainnet_address("Controller"), gas_price=GAS_PRICE
    )

    ###
    # All of this we will need to do through the governance proxy from the multisig after deployment
    ###

    Controller[0].setDefaultPoolAdapter(
        curve_adapter, {"gas_price": GAS_PRICE, "from": deployer}
    )
