from __future__ import annotations

import inspect
from dataclasses import dataclass
from typing import ClassVar, Generic, List, Tuple, TypeVar, cast

T = TypeVar("T")


@dataclass
class TrackedNumber(Generic[T]):
    _history: ClassVar[List[Tuple[str, TrackedNumber]]] = []

    def _log_number(self, number: T):
        curframe = inspect.currentframe()
        calframe = inspect.getouterframes(curframe, 2)
        formatted_frame = " -> ".join(
            f"{c.function} ({c.lineno})" for c in calframe[3:6][::-1]
        )
        self._history.append((formatted_frame, cast(TrackedNumber, number)))

    @classmethod
    @property
    def history(cls) -> List[Tuple[str, T]]:
        return cast(List[Tuple[str, T]], cls._history)
