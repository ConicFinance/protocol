import json
from decimal import Decimal

from brownie import GovernanceProxy
from support.constants import GAS_PRICE  # type: ignore
from support.utils import load_deployer_account
from brownie.project.main import get_loaded_projects


def get_delays():
    config_path = (
        get_loaded_projects()[0]._path
        / "scripts"
        / "deployment"
        / "governance-proxy-config.json"
    )
    with config_path.open() as fp:
        return json.load(fp)


def main():
    deployer = load_deployer_account()
    params = {"from": deployer, "gas_price": GAS_PRICE}
    governance_proxy = GovernanceProxy[0]

    delays = get_delays()
    calls = [
        (
            governance_proxy.address,
            governance_proxy.updateDelay.encode_input(
                delay["selector"], Decimal(delay["delay"]) * 86400
            ),
        )
        for delay in delays
        if delay["critical"] and Decimal(delay["delay"]) > 0
    ]
    governance_proxy.requestChange(calls, params)
