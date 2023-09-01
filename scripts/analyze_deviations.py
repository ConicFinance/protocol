import gzip
import json
from os import path
from statistics import quantiles
import tabulate

ROOT_DIR = path.dirname(path.dirname(path.abspath(__file__)))
DEVIATIONS_PATH = path.join(ROOT_DIR, "build", "deviations.json.gz")

POOL_NAMES = {
    "0x0CD6f267b2086bea681E922E19D40512511BE538": "crvUSDFRAX-f",
    "0x0f3159811670c117c372428D4E69AC32325e4D0F": "rETH-f",
    "0x390f3595bCa2Df7d23783dFd126427CCeb997BF4": "crvUSDUSDT-f",
    "0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E": "crvUSDUSDC-f",
    "0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A": "cbETH/ETH-f",
    "0x5a6A4D54456819380173272A5E8E9B9904BdF41B": "MIM-3LP3CRV-f",
    "0xA5407eAE9Ba41422680e2e00537571bcC53efBfD": "crvPlain3andSUSD",
    "0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0": "crvUSDUSDP-f",
    "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022": "steCRV",
    "0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2": "crvFRAX",
    "0xaE34574AC03A15cd58A92DC79De7B1A0800F1CE3": "crvfraxUSDP",
    "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7": "3Crv",
    "0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B": "FRAX3CRV-f",
}

CL_DEVIATION_THRESHOLDS = {
    "crvFRAX[0-1]": 100,
    "FRAX3CRV-f[0-1]": 100,
    "crvPlain3andSUSD[0-1]": 25,
    "crvPlain3andSUSD[0-2]": 25,
    "crvPlain3andSUSD[0-3]": 50,
    "3Crv[0-1]": 25,
    "3Crv[0-2]": 25,
    "MIM-3LP3CRV-f[0-1]": "?",
    "crvfraxUSDP[0-1]": 100,
    "crvUSDUSDC-f[0-1]": 25,
    "crvUSDUSDT-f[0-1]": 25,
    "crvUSDUSDP-f[0-1]": 100,
    "crvUSDFRAX-f[0-1]": 100,
    "steCRV[0-1]": 100,
    "cbETH/ETH-f[0-1]": 100,
    "rETH-f[0-1]": 200,
}


fees = {
    "0x0CD6f267b2086bea681E922E19D40512511BE538": 1.0,
    "0x0f3159811670c117c372428D4E69AC32325e4D0F": 3.87519,
    "0x390f3595bCa2Df7d23783dFd126427CCeb997BF4": 1.0,
    "0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E": 1.0,
    "0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A": 3.91355,
    "0x5a6A4D54456819380173272A5E8E9B9904BdF41B": 4.0,
    "0xA5407eAE9Ba41422680e2e00537571bcC53efBfD": 2.0,
    "0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0": 1.0,
    "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022": 1.0,
    "0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2": 1.0,
    "0xaE34574AC03A15cd58A92DC79De7B1A0800F1CE3": 1.0,
    "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7": 1.0,
    "0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B": 4.0,
}

with gzip.open(DEVIATIONS_PATH) as f:
    items = [json.loads(line) for line in f]

per_pool = {}
for item in items:
    for pool, deviations in item["deviations"].items():
        for i, deviation in enumerate(deviations):
            per_pool.setdefault((pool, i), [])
            per_pool[(pool, i)].append(deviation)


results = []
for (pool, i), deviations in per_pool.items():
    pool_name = POOL_NAMES[pool]
    quantile_99 = quantiles(deviations, n=100)[98]
    quantile_499 = quantiles(deviations, n=500)[498]
    quantile_999 = quantiles(deviations, n=1000)[998]
    name = f"{pool_name}[0-{i+1}]"
    threshold = CL_DEVIATION_THRESHOLDS[name]
    results.append(
        [
            name,
            quantile_99,
            quantile_499,
            quantile_999,
            threshold,
            fees[pool],
        ]
    )

table = tabulate.tabulate(
    results,
    headers=["name", "q99", "q499", "q999", "cl threshold", "fee"],
    tablefmt="github",
)
print(table)
