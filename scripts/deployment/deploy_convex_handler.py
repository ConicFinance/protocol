from brownie import ConvexHandler, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account


def main():
    deployer = load_deployer_account()
    convex_handler = deployer.deploy(ConvexHandler, Controller[0], gas_price=GAS_PRICE)
    Controller[0].setConvexHandler(
        convex_handler, {"gas_price": GAS_PRICE, "from": deployer}
    )
    return convex_handler
