from brownie import LpTokenStaker, Controller, EmergencyMinter, interface
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    deployer = load_deployer_account()
    lp_token_staker = deployer.deploy(
        LpTokenStaker, Controller[0], CNC, EmergencyMinter[0], gas_price=GAS_PRICE
    )
    Controller[0].setLpTokenStaker(
        lp_token_staker, {"from": deployer, "gas_price": GAS_PRICE}
    )
    cnc = interface.ICNCToken(CNC)
    cnc.addMinter(lp_token_staker, {"from": deployer, "gas_price": GAS_PRICE})
    return lp_token_staker
