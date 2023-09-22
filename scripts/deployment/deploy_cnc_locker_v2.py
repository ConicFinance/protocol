from brownie import CNCLockerV3, LpTokenStaker, Controller
from support.constants import GAS_PRICE, MULTISIG_ADDRESS, LOCKER_V2_MERKLE_ROOT  # type: ignore
from support.utils import load_deployer_account
from support.addresses import *  # type: ignore


def main():
    return load_deployer_account().deploy(
        CNCLockerV3,
        Controller[0],
        CNC,
        MULTISIG_ADDRESS,
        CRV,
        CVX,
        LOCKER_V2_MERKLE_ROOT,
        gas_price=GAS_PRICE,
    )
