from __future__ import annotations

import asyncio
from pathlib import Path
from typing import List, Optional


class URandomSource:
    """Fallback RNG based on /dev/urandom."""

    def __init__(self, device: str = "/dev/urandom", chunk_bytes: int = 4096) -> None:
        self.device = Path(device)
        self.chunk_bytes = chunk_bytes
        self._handle: Optional[object] = None

    def close(self) -> None:
        if self._handle:
            try:
                self._handle.close()
            finally:
                self._handle = None

    async def read_chunk(self) -> bytes:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._blocking_read)

    def _blocking_read(self) -> bytes:
        if self._handle is None:
            self._handle = self.device.open("rb", buffering=0)
        data = self._handle.read(self.chunk_bytes)
        if not data:
            raise RuntimeError("No data from urandom")
        return data

    async def pump_bits(self, queue: "asyncio.Queue[int]", stop_flag) -> None:
        while not stop_flag.is_set():
            chunk = await self.read_chunk()
            for bit in bytes_to_bits(chunk):
                await queue.put(bit)


def bytes_to_bits(data: bytes) -> List[int]:
    bits: List[int] = []
    for byte in data:
        for shift in range(8):
            bits.append((byte >> shift) & 1)
    return bits

