from dataclasses import dataclass
import resource
import subprocess
import time


@dataclass
class Stats:
    wall_ms: float
    user_ms: float
    system_ms: float


def invoke(cmd: list[str]) -> Stats:
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    wall_start = time.perf_counter()
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process.communicate()
    wall_ms = (time.perf_counter() - wall_start) * 1000
    after = resource.getrusage(resource.RUSAGE_CHILDREN)

    user_ms = (after.ru_utime - before.ru_utime) * 1000
    system_ms = (after.ru_stime - before.ru_stime) * 1000

    return Stats(
        wall_ms=round(wall_ms, 5),
        user_ms=round(user_ms, 5),
        system_ms=round(system_ms, 5),
    )


def get_cmd(cmd_str: str) -> list[str]:
    return cmd_str.split(" ")


def benchmark(cmd: list[str], warmup_runs: int = 3, benchmark_runs: int = 5) -> list[Stats]:
    for _ in range(warmup_runs):
        invoke(cmd)
    stats = []
    for _ in range(benchmark_runs):
        stats.append(invoke(cmd))
    return stats


def benchmark_all(output_file: str = "bench.csv") -> list[Stats]:
    rows = ["name,which,file,run_no,wall_ms,user_ms,system_ms"]
    for bench in BENCHES:
        sort_stats = benchmark(get_cmd(bench["sort"] + " " + bench["file"]))
        msort_stats = benchmark(get_cmd(bench["msort"] + " " + bench["file"]))
        for i, (s, m) in enumerate(zip(sort_stats, msort_stats), start=1):
            rows.append(f"{bench['name']},sort,{bench['file']},{i},{s.wall_ms},{s.user_ms},{s.system_ms}")
            rows.append(f"{bench['name']},msort,{bench['file']},{i},{m.wall_ms},{m.user_ms},{m.system_ms}")
    with open(output_file, "w") as f:
        f.write("\n".join(rows))


BENCHES = [
    {
        "name": "baseline_small",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/baseline_10000.txt"
    },
    {
        "name": "baseline",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/baseline_1000000.txt"
    },
    {
        "name": "baseline_quicksort",
        "sort": "sort -S 8M -o sort.out --parallel 1 --qsort",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out --qsort",
        "file": "data/baseline_1000000.txt"
    },
    {
        "name": "baseline_numeric",
        "sort": "sort -S 8M -n -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -n -o msort.out",
        "file": "data/baseline_1000000.txt"
    },
    {
        "name": "baseline_reverse",
        "sort": "sort -S 8M -r -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -r -o msort.out",
        "file": "data/baseline_1000000.txt"
    },
    {
        "name": "sorted",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/sorted_1000000.txt"
    },
    {
        "name": "sorted_desc",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/sorted_desc_1000000.txt"
    },
    {
        "name": "partial_sorted",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/partial_sorted_1000000.txt"
    },
    {
        "name": "duplicate",
        "sort": "sort -S 8M -u -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -u -o msort.out",
        "file": "data/duplicate_1000000.txt"
    },
    {
        "name": "logs",
        "sort": "sort -S 8M -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 8M -o msort.out",
        "file": "data/logs_1000000.txt"
    },
    {
        "name": "tpch",
        "sort": "sort -S 16M -t| -k 11,11 -k 14,14 -k 15,15 -o sort.out --parallel 1",
        "msort": "./zig-out/bin/msort -S 16M -t '|' -k 11,11 -k 14,14 -k 15,15 -o msort.out",
        "file": "data/lineitem_1000000.tbl"
    }
]


if __name__ == "__main__":
    benchmark_all()
