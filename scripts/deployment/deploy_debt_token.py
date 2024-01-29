from brownie import ConicDebtToken
from support.constants import DEBT_TOKEN_MERKLE_ROOT, GAS_PRICE, REFUNDS_MERKLE_ROOT

from support.utils import load_deployer_account


def main():
    deployer = load_deployer_account()
    deployer.deploy(
        ConicDebtToken, DEBT_TOKEN_MERKLE_ROOT, REFUNDS_MERKLE_ROOT, gas_price=GAS_PRICE
    )
