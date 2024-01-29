from brownie import LpTokenStaker, Controller, interface
from support.constants import GAS_PRICE, TREASURY_ADDRESS  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    deployer = load_deployer_account()
    lp_token_staker = deployer.deploy(
        LpTokenStaker, Controller[0], CNC, TREASURY_ADDRESS, gas_price=GAS_PRICE
    )
    Controller[0].initialize(
        lp_token_staker, {"from": deployer, "gas_price": GAS_PRICE}
    )
    # cnc = interface.ICNCToken(CNC)
    # cnc.addMinter(lp_token_staker, {"from": deployer, "gas_price": GAS_PRICE})
    # return lp_token_staker
