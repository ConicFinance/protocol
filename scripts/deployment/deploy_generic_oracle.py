from brownie import GenericOracle
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account, get_mainnet_address


def main():
    deployer = load_deployer_account()
    generic_oracle = deployer.deploy(GenericOracle, gas_price=GAS_PRICE)

    params = {"from": deployer, "gas_price": GAS_PRICE}
    generic_oracle.initialize(
        get_mainnet_address("CurveLPOracle"),
        get_mainnet_address("ChainlinkOracle"),
        params,
    )
    gov_proxy = get_mainnet_address("GovernanceProxy")
    generic_oracle.transferOwnership(gov_proxy, params)

    ###
    # All of this we will need to do through the governance proxy from the multisig after deployment
    ###

    # Controller[0].setPriceOracle(generic_oracle, {"from": deployer, "gas_price": GAS_PRICE})

    return generic_oracle
