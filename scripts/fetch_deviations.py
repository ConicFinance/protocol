from decimal import Decimal as D
import logging
import json
from os import path
from typing import Dict, List
from brownie import CurveRegistryCache, interface  # type: ignore
from dataclasses import dataclass

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

OUTPUT_FILE = "build/deviations.json"
NEW_ORACLE_DEPLOYMENT_BLOCK = 17613381
BLOCK_INTERVAL = 3600 * 3 // 12  # 3 hours in blocks


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, D):
            return float(obj.quantize(D(10) ** -5))
        return json.JSONEncoder.default(self, obj)


CRV_USD = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
CURVE_POOLS_ADDRESS = {
    "0xA5407eAE9Ba41422680e2e00537571bcC53efBfD",
    "0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A",
    "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
    "0x0f3159811670c117c372428D4E69AC32325e4D0F",
    "0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2",
    "0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E",
    "0x390f3595bCa2Df7d23783dFd126427CCeb997BF4",
    "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022",
    "0x0CD6f267b2086bea681E922E19D40512511BE538",
    "0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B",
    "0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0",
    "0x5a6A4D54456819380173272A5E8E9B9904BdF41B",
    "0xaE34574AC03A15cd58A92DC79De7B1A0800F1CE3",
}


@dataclass
class Coin:
    address: str
    name: str
    decimals: int


class AssetType:
    USD = 0
    ETH = 1
    BTC = 2
    OTHER = 3
    CRYPTO = 4


@dataclass
class CurvePool:
    address: str
    asset_type: int
    coins: List[Coin]


class DataFetcher:
    def __init__(self, registry: CurveRegistryCache, oracles: List[interface.IOracle]):
        self.registry = registry
        self.oracles = oracles
        self.curve_pools = self._fetch_curve_pools()

    def _fetch_curve_pools(self) -> List[CurvePool]:
        return [self._fetch_curve_pool(address) for address in CURVE_POOLS_ADDRESS]

    def _fetch_curve_pool(self, address: str) -> CurvePool:
        coin_addresses = self.registry.coins(address)
        decimals = [interface.ERC20(coin).decimals() for coin in coin_addresses]
        names = [interface.ERC20(coin).name() for coin in coin_addresses]
        coins = [Coin(*args) for args in zip(coin_addresses, names, decimals)]
        asset_type = self.registry.assetType(address)
        return CurvePool(address, asset_type, coins)

    def fetch_all_deviations(self, block: int) -> Dict[str, List[D]]:
        result = {}
        for pool in self.curve_pools:
            try:
                result[pool.address] = self.fetch_pool_deviations(pool, block)
            except Exception as e:
                logging.error(
                    "Error fetching pool %s at block %s: %s", pool.address, block, e
                )
        return result

    def fetch_pool_deviations(self, pool: CurvePool, block: int) -> List[D]:
        prices = self._fetch_prices(pool, block)
        from_decimals = pool.coins[0].decimals
        from_balance = 10**from_decimals
        from_price = prices[0]
        deviations = []
        for i in range(1, len(pool.coins)):
            to_decimals = pool.coins[i].decimals
            to_price = prices[i]
            to_expected_unscaled = D(from_balance * from_price) / to_price
            to_expected = self._convert_scale(
                to_expected_unscaled, from_decimals, to_decimals
            )
            Pool = (
                interface.ICurvePoolV2
                if pool.asset_type == AssetType.CRYPTO
                else interface.ICurvePoolV1
            )
            to_actual = D(
                Pool(pool.address).get_dy(0, i, from_balance, block_identifier=block)
            )
            deviation_bps = (
                abs(to_expected - to_actual) / max(to_expected, to_actual) * 10_000
            )
            deviations.append(deviation_bps)
        return deviations

    @staticmethod
    def _convert_scale(value: D, from_decimals: int, to_decimals: int) -> D:
        if from_decimals == to_decimals:
            return value
        elif from_decimals > to_decimals:
            return value / D(10 ** (from_decimals - to_decimals))
        else:
            return value * D(10 ** (to_decimals - from_decimals))

    def _fetch_prices(self, pool: CurvePool, block: int) -> List[D]:
        return [self._fetch_price(coin.address, block) for coin in pool.coins]

    def _fetch_price(self, asset: str, block: int) -> D:
        return D(self.get_oracle(block).getUSDPrice(asset, block_identifier=block))

    def get_oracle(self, block) -> interface.IOracle:
        if block >= NEW_ORACLE_DEPLOYMENT_BLOCK:
            return self.oracles[1]
        return self.oracles[0]


def main():
    registry = CurveRegistryCache.at("0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9")
    new_oracle = interface.IOracle("0x286eF89cD2DA6728FD2cb3e1d1c5766Bcea344b0")
    old_oracle = interface.IOracle("0x46fa6F8CC35c1F464eA78196080f5Cfd1d76F6E9")
    fetcher = DataFetcher(registry, [old_oracle, new_oracle])

    blocks_seen = set()
    if path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE) as f:
            blocks_seen = [json.loads(line)["block"] for line in f]
    with open(OUTPUT_FILE, "a") as f:
        for block in range(16_800_000, 17871900, BLOCK_INTERVAL):
            if block in blocks_seen:
                continue
            logging.info("Fetching block %s", block)
            deviations = fetcher.fetch_all_deviations(block)
            encoded = json.dumps(
                {"block": block, "deviations": deviations}, cls=DecimalEncoder
            )
            f.write(encoded + "\n")
            f.flush()
