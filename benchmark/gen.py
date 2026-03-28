import pathlib
import random
import string
from datetime import datetime, timezone


def write(filename: str, data: list[str]) -> None:
    actual_filename = filename + "_" + str(len(data)) + ".txt"
    with (pathlib.Path("data") / actual_filename).open("w") as f:
        for line in data:
            f.write(line + "\n")


def baseline(n: int, maximum: int = 1000000) -> list[str]:
    """
    Generate a list of n random integers.
    """
    return [str(random.randint(1, maximum)) for _ in range(n)]


def duplicate(n: int) -> None:
    """
    Generate a list of n integers, from 1 to 10.
    """
    return baseline(n, 10)


def sorted(n: int, asc: bool = True) -> None:
    """
    Generate a list of n integers, in sorted order from 1 to n (or descending).
    """
    data = baseline(n)
    data.sort(reverse=not asc)
    return data


def partial_sorted(n: int, asc: bool = True, swap_factor: float = 0.1) -> list[str]:
    """
    Same multiset as baseline/sorted, fully sorted first, then random swaps so
    order is only partially preserved (typical sort stress case).
    """
    data = baseline(n)
    data.sort(reverse=not asc)
    swap_count = int(n * swap_factor)
    for _ in range(swap_count):
        i = random.randrange(n)
        j = random.randrange(n)
        data[i], data[j] = data[j], data[i]
    return data




def logs(n: int) -> list[str]:
    """
    One synthetic log line per row. Format (space-separated, key fields fixed order):

        <UTC_ISO_MS>Z <LEVEL> <file>:<line> <message>

    Example:
        2024-07-19T14:02:33.041Z WARNING net/handler.go:8921 upstream deadline exceeded req=7a3f
    """
    def _random_alnum(length: int) -> str:
        alphabet = string.ascii_letters + string.digits
        return "".join(random.choices(alphabet, k=length))


    def _random_utc_timestamp() -> str:
        dt = datetime(
            random.randint(2020, 2026),
            random.randint(1, 12),
            random.randint(1, 28),
            random.randint(0, 23),
            random.randint(0, 59),
            random.randint(0, 59),
            random.randint(0, 999_999),
            tzinfo=timezone.utc,
        )
        return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    levels = ("INFO", "WARNING", "ERROR")
    exts = ("zig", "rs", "c", "go", "ts")
    verbs = ("started", "failed", "retrying", "timeout", "ok", "skipped", "panic")
    nouns = ("merge", "socket", "buffer", "parse", "alloc", "flush", "decode")

    lines: list[str] = []
    for _ in range(n):
        ts = _random_utc_timestamp()
        level = random.choice(levels)
        fname = f"{_random_alnum(6)}.{random.choice(exts)}"
        line_no = random.randint(1, 500_000)
        msg = f"{random.choice(verbs)} {random.choice(nouns)} {_random_alnum(8)}"
        lines.append(f"{ts} {level} {fname}:{line_no} {msg}")
    return lines


def tpch() -> None:
    print("Download lineitem tpch data from: https://www.kaggle.com/datasets/fven7u/tpch-1gb?resource=download")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("-n", "--number", type=int, default=1000000)
    parser.add_argument("-t", "--type", type=str, default="baseline")
    args = parser.parse_args()

    if args.type == "baseline":
        data = baseline(args.number)
    elif args.type == "duplicate":
        data = duplicate(args.number)
    elif args.type == "sorted":
        data = sorted(args.number, asc=True)
    elif args.type == "sorted_desc":
        data = sorted(args.number, asc=False)
    elif args.type == "partial_sorted":
        data = partial_sorted(args.number, asc=True)
    elif args.type == "logs":
        data = logs(args.number)
    elif args.type == "tpch":
        tpch()
    else:
        raise ValueError(f"Invalid type: {args.type}")

    if args.type != "tpch":
        write(args.type, data)