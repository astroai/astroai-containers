#!/usr/bin/env python3
"""Distributed Ray smoke test — run against a live cluster."""

from __future__ import annotations

import sys

import ray


@ray.remote
def add(a: int, b: int) -> int:
    return a + b


@ray.remote
def hostname() -> str:
    import socket

    return socket.gethostname()


def main() -> int:
    ray.init(address="auto")
    nodes = len(ray.nodes())
    print(f"Connected; {nodes} node(s) visible")
    results = ray.get([add.remote(i, i) for i in range(4)])
    hosts = ray.get([hostname.remote() for _ in range(2)])
    print("add results:", results)
    print("worker hosts:", hosts)
    if nodes < 2:
        print("WARN: expected at least 2 nodes (head + worker)", file=sys.stderr)
        return 1
    if results != [0, 2, 4, 6]:
        return 1
    print("OK: distributed smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
