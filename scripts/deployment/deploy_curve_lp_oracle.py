from brownie import CurveLPOracle, GenericOracle, ChainlinkOracle, Controller
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account


def main():
    deployer = load_deployer_account()
    curve_lp_oracle = deployer.deploy(
        CurveLPOracle, GenericOracle[0], Controller[0], gas_price=GAS_PRICE
    )
    GenericOracle[0].initialize(
        curve_lp_oracle, ChainlinkOracle[0], {"from": deployer, "gas_price": GAS_PRICE}
    )
    return curve_lp_oracle
