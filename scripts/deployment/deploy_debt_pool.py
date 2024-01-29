from brownie import DebtPool

from support.constants import GAS_PRICE
from support.utils import get_mainnet_address, load_deployer_account


def main():
    deployer = load_deployer_account()
    debt_token = get_mainnet_address("ConicDebtToken")
    deployer.deploy(DebtPool, debt_token, gas_price=GAS_PRICE)
