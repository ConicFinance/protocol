import os
import datetime as dt
from decimal import Decimal

DEPLOYER_ADDRESS = "0xedaEb101f34d767f263c0fe6B8d494E3d071F0bA"

TOTAL_SUPPLY = 10_000_000
AIRDROP_AMOUNT = 10_000_000 * Decimal("0.1")
AIRDROP_DURATION = dt.timedelta(days=180).total_seconds()
VESTING_DURATION = dt.timedelta(days=365).total_seconds()

GAS_PRICE = f"{os.environ.get('GAS_PRICE', '50')} gwei"

MULTISIG_ADDRESS = "0xB27DC5f8286f063F11491c8f349053cB37718bea"
VETO_MULTISIG_ADDRESS = "0x5a2E9f203dA3e6DD9D0C5F6366df4Df98a54bC0C"
AIRDROP_MERKLE_ROOT = (
    "0x6739cad78963b57512820d243d424454b501f89fe019854f6efa1051078105b2"
)
WHITELIST_MERKLE_ROOT = (
    "0x76de4ca3f6408ee275c14b56674b52851e1e2bf23bff37cb9bcca2bc868a8406"
)
LOCKER_V2_MERKLE_ROOT = (
    "0x1fb27a93b1597fb63a71400761fa335d34875bc82ed5d1e2182cbb0a966049a7"
)
CONIC_V2_LOCKER_MERKLE_ROOT = (
    "0xdb5e1bfbc1c8e7f169a5d5ca031d8a814267b7fe0af8f3eca2dc0a8a942719c5"
)

TREASURY_ADDRESS = "0xB27DC5f8286f063F11491c8f349053cB37718bea"

LAST_REBALANCING_REWARD_HANDLER_ADDRESS = "0x4D080be793fb7934a920cbDd95010b893AEda545"


REFUNDS_MERKLE_ROOT = (
    "0x14210f766ecf973c2198e65bc2e29c865dea64727411df17e6b9723fcf08341a"
)

DEBT_TOKEN_MERKLE_ROOT = (
    "0xe2520b7aa640dc81622dee43fdb344a15a6ab069853ab0a50844e0a9e95e99cd"
)
