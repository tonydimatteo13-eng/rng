from __future__ import annotations

import asyncio
import random
from typing import List


class FakeRNG:
    """Deterministic RNG for demos and tests."""

    def __init__(self, seed: int | None = None, chunk_bits: int = 4096) -> None:
        self.random = random.Random(seed)
        self.chunk_bits = chunk_bits

    async def pump_bits(self, queue: "asyncio.Queue[int]", stop_flag, bias: float = 0.0) -> None:
        flip_every = int(1 / bias) if bias > 0 else 0
        counter = 0
        while not stop_flag.is_set():
            bits = self._generate_bits()
            if bias > 0:
                for idx in range(len(bits)):
                    counter += 1
                    if flip_every and counter % flip_every == 0:
                        bits[idx] ^= 1
            for bit in bits:
                await queue.put(bit)
            await asyncio.sleep(0)

    def _generate_bits(self) -> List[int]:
        return [self.random.randint(0, 1) for _ in range(self.chunk_bits)]

