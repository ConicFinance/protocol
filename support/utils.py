import json
from brownie import accounts
from brownie.project.main import get_loaded_projects


from support.constants import DEPLOYER_ADDRESS


def get_account(address: str):
    return [acc for acc in accounts if acc.address == address][0]


def get_mainnet_address(contract: str) -> str:
    config_path = get_loaded_projects()[0]._path / "build" / "deployments" / "map.json"
    with config_path.open() as fp:
        return json.load(fp)["1"][contract][0]


def load_deployer_account():
    if not accounts:
        accounts.connect_to_clef()
    return get_account(DEPLOYER_ADDRESS)
