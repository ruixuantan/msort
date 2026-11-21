# msort

A hobby project in Zig to learn sorting algorithms and explore building a faster,
lower-memory clone of Unix `sort`. It implements a subset of `sort` with a focus on
SIMD and keeping memory use small.

- SIMD accelerates byte comparisons and field-separator scanning.
- Merge sort and quicksort, with numeric, reverse, unique, and field-based sorting.
- Lines are represented by offsets into input buffers instead of copied strings.
  Larger inputs spill to temporary files and are combined with a loser-tree k-way merge.
- Configurable memory budget (`-m=8M` by default); this is a buffer budget, not a
  hard limit on process memory.

## Build and test

Requires Zig **0.17.1** and Make.

```sh
make build        # Fast optimized build
make build-debug  # Debug build
make test         # Unit tests
```

The executable is written to `zig-out/bin/msort`.

## Usage

```sh
./zig-out/bin/msort test_data/test_26.txt
./zig-out/bin/msort -n -r numbers.txt
./zig-out/bin/msort -s=, -k=2n test_data/test_csv.csv
./zig-out/bin/msort --help
```

Options go before filenames; value options use `=`, and field indexes start at
**0**. With no input files, msort reads stdin. Ordering is bytewise; use
`LC_ALL=C` when comparing with Unix `sort`.

To avoid spilling a single file, its bytes must fit in the input buffer (half of
`-m`) and its line descriptors must fit in the line table (a quarter of `-m`).
For example, `-m=256M` keeps the 125 MB, one-million-row LINEITEM sample in one run.

## A quick benchmark against Unix `sort`

Baseline at `e450b71` on an Apple M4 with 24 GB RAM, macOS 27.2.1, and Zig 0.17.1
in fast mode, compared with macOS `/usr/bin/sort` 2.3-Apple (201). Both commands explicitly
set `--parallel=1`; msort's sorting code is currently single-threaded. Measured
with `crap -d 3000`, default memory settings for both programs, `LC_ALL=C`, and
output written to `/dev/null`. Times are means; memory is mean peak RSS reported
by `crap`.

- **1,000,000 lines, 125 MB:** msort **146 ms / 8.46 MB**, macOS `/usr/bin/sort`
  **261 ms / 179 MB** (21 and 12 runs, respectively).
- **6,001,215 lines, 754 MB:** msort **994 ms / 8.64 MB**, macOS `/usr/bin/sort`
  **1.74 s / 1.09 GB** (4 and 3 runs, respectively).

After optimizing byte comparisons and loser-tree replay, msort wall times fell
from **149 to 120 ms** and **993 to 762 ms**, respectively, in a separate
before/after test (medians of seven alternating warm runs at `-m=8M`, stdout
to `/dev/null`). Both datasets still matched `LC_ALL=C /usr/bin/sort` byte for
byte. These are local measurements; performance varies with the input and machine.

msort has a narrower feature set than Unix `sort`, so it has fewer cases and
compatibility details to handle. That simpler implementation can contribute to
the speed difference alongside SIMD; these measurements compare the overall
programs.

The input data comes from the [TPC-H](https://www.tpc.org/tpch/) `LINEITEM` table at scale factor 1.
