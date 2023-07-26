from brownie import Controller, GovernanceProxy  # type: ignore
import json
from support.types import WeightUpdate
import os

LAV_FILE = os.environ.get("LAV_FILE")
assert LAV_FILE, """no lav file provided with LAV_FILE env var,
usage: LAV_FILE=config/lavs/2023-03-28.json brownie run scripts/encode_weights.py --network mainnet"""


def main():
    with open(LAV_FILE) as f:
        data = json.load(f)
    updates = [WeightUpdate.from_dict(v) for v in data]
    print("Governance proxy address:", GovernanceProxy[0].address)
    print("Function name: requestChange")
    print("Argument:")
    data = Controller[0].updateAllWeights.encode_input(updates)
    print(f'[["{Controller[0].address}", "{data}"]]')
