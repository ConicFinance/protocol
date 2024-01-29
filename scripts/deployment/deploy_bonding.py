from decimal import Decimal
from brownie import interface, Bonding
from support.constants import GAS_PRICE, TREASURY_ADDRESS  # type: ignore
from support.utils import get_mainnet_address, load_deployer_account
from support.addresses import CRV_USD, CNC

TOTAL_NUMBER_OF_EPOCHS = 52
EPOCH_DURATION = 86_400 * 7
BONDING_PRICE_INCREASE_FACTOR = 2 * 10**18
CNC_START_PRICE = Decimal("4.5") * 10**18


def main():
    deployer = load_deployer_account()
    controller = get_mainnet_address("Controller")
    locker = get_mainnet_address("CNCLockerV3")
    crvusd_pool = interface.IConicPool(get_mainnet_address("ConicPool", 1))
    assert crvusd_pool.underlying() == CRV_USD, "Invalid CRVUSD pool"

    bonding = deployer.deploy(
        Bonding,
        locker,
        controller,
        TREASURY_ADDRESS,
        crvusd_pool,
        EPOCH_DURATION,
        TOTAL_NUMBER_OF_EPOCHS,
        gas_price=GAS_PRICE,
    )
    bonding.setCncPriceIncreaseFactor(
        BONDING_PRICE_INCREASE_FACTOR, {"from": deployer, "gas_price": GAS_PRICE}
    )
    bonding.setCncStartPrice(
        CNC_START_PRICE, {"from": deployer, "gas_price": GAS_PRICE}
    )
