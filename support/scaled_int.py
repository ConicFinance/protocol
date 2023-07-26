from __future__ import annotations

import functools
import math
from dataclasses import dataclass
from typing import List, Tuple, Union

from support.tracked_number import TrackedNumber


@dataclass
@functools.total_ordering
class ScaledInt(TrackedNumber["ScaledInt"]):
    value: int
    decimals: int = 18

    def __post_init__(self):
        self._log_number(self)

    @classmethod
    def from_int(cls, value, decimals=18):
        return cls(value * 10**decimals, decimals)

    @classmethod
    def from_fixed(cls, value: int, decimals=18):
        return cls(value, decimals)

    def sqrt(self):
        return ScaledInt(
            int(math.sqrt(self.value * 10**self.decimals)), self.decimals
        )

    def __add__(self, other: ScaledInt) -> ScaledInt:
        assert self.decimals == other.decimals, "Decimals must be the same"
        return ScaledInt(self.value + other.value, self.decimals)

    def __sub__(self, other: ScaledInt) -> ScaledInt:
        assert self.decimals == other.decimals, "Decimals must be the same"
        return ScaledInt(self.value - other.value, self.decimals)

    def __neg__(self):
        return ScaledInt(-self.value, self.decimals)

    def __mul__(self, other: Union[ScaledInt, int]) -> ScaledInt:
        if isinstance(other, int):
            return ScaledInt(self.value * other, self.decimals)
        assert self.decimals == other.decimals, "Decimals must be the same"
        return ScaledInt(self.value * other.value // 10**self.decimals, self.decimals)

    def __rmul__(self, other: Union[ScaledInt, int]) -> ScaledInt:
        return self * other

    def __truediv__(self, other: Union[ScaledInt, int]) -> ScaledInt:
        if isinstance(other, int):
            return ScaledInt(self.value // other, self.decimals)
        assert self.decimals == other.decimals, "Decimals must be the same"
        return ScaledInt(self.value * 10**self.decimals // other.value, self.decimals)

    def __pow__(self, exp: int) -> ScaledInt:
        result = ScaledInt.from_int(1, self.decimals)
        for _ in range(exp):
            result *= self
        return result

    def __eq__(self, other: Union[ScaledInt, int]) -> bool:
        if isinstance(other, int):
            other = ScaledInt.from_int(other, self.decimals)
        return self.value == other.value and self.decimals == other.decimals

    def __lt__(self, other: Union[ScaledInt, int]) -> bool:
        if isinstance(other, int):
            other = ScaledInt.from_int(other, self.decimals)
        assert self.decimals == other.decimals, "Decimals must be the same"
        return self.value < other.value

    def __abs__(self) -> ScaledInt:
        return ScaledInt(abs(self.value), self.decimals)

    def to_float(self) -> float:
        return self.value / 10**self.decimals

    def downscale(self, decimals: int) -> ScaledInt:
        return ScaledInt(self.value // 10 ** (self.decimals - decimals), decimals)

    def upscale(self, decimals: int) -> ScaledInt:
        return ScaledInt(self.value * 10 ** (decimals - self.decimals), decimals)

    @classmethod
    def get_topn(cls, n=5) -> List[Tuple[str, int]]:
        return sorted([(k, abs(r.value)) for k, r in cls.history], key=lambda x: -x[1])[
            :n
        ]
