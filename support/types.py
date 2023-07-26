from typing import NamedTuple, List


class Status:
    Pending = 0
    Canceled = 1
    Executed = 2


class Change(NamedTuple):
    status: int
    id: int
    requested_at: int
    delay: int
    ended_at: int
    calls: tuple


class PoolWeights(NamedTuple):
    poolAddress: str
    weight: int


class WeightUpdate(NamedTuple):
    address: str
    weights: List[PoolWeights]

    @classmethod
    def from_dict(cls, data: dict) -> "WeightUpdate":
        return cls(
            address=data["address"],
            weights=[PoolWeights(**pool) for pool in data["weights"]],
        )
