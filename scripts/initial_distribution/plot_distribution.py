import argparse

import matplotlib
import matplotlib.pyplot as plt

font = {"family": "DejaVu Sans", "size": 14}

matplotlib.rc("font", **font)

parser = argparse.ArgumentParser(prog="plot-distribution")
parser.add_argument("-o", "--output", help="Output file")

args = parser.parse_args()

colors = [
    "#2076ed",
    "#fb5a5a",
    "#83f5a1",
    "#2d62b1",
    "#fdd75c",
]


total_supply = 10_000_000
initial_tranche = 0.14 * 10_000_000
reduction_ratio = 0.5333
eth_per_tranche = 14
current_tranche_size = initial_tranche
exchange_rate = initial_tranche / eth_per_tranche
tokens_distributed = 0
eth_spent = 0


def _to_perc_supply(value):
    return value / total_supply * 100


prev_eth_spent = eth_spent
prev_tokens_distributed = tokens_distributed

for i in range(10):
    eth_spent += eth_per_tranche
    tokens_distributed += current_tranche_size

    x = [prev_eth_spent, eth_spent]
    y_raw = [prev_tokens_distributed, tokens_distributed]
    y = list(map(_to_perc_supply, y_raw))

    plt.plot(x, y, color=colors[i % len(colors)])

    prev_eth_spent = eth_spent
    prev_tokens_distributed = tokens_distributed

    current_tranche_size *= reduction_ratio
    exchange_rate *= reduction_ratio

    print("ETH spent: ", eth_spent)
    print("Exchange rate: ", exchange_rate)
    print("Valuation : ", total_supply / exchange_rate * 3500)
    print()

plt.xlabel("Total ETH contributed")
plt.ylabel("Percentage of total CNC distributed")

if args.output:
    plt.tight_layout()
    plt.savefig(args.output)
else:
    plt.show()
