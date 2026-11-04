# msort

A hobby project in Zig to learn sorting algorithms and explore building a faster,
lower-memory clone of Unix `sort`. It implements a subset of `sort` with a focus on
SIMD and keeping memory use small.

- SIMD accelerates byte comparisons and field-separator scanning.
- Merge sort and quicksort, with numeric, reverse, unique, and field-based sorting.
- Lines are represented by offsets into input buffers instead of copied strings.
  Larger inputs spill to temporary files and are combined with a k-way merge.
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

## A quick benchmark

Local results on an Apple M4 with 24 GB RAM, macOS 26.6.2, and Zig 0.17.0 in fast
mode, compared with macOS `/usr/bin/sort` 2.3-Apple (199). Both commands explicitly
set `--parallel=1`; msort's sorting code is currently single-threaded. Measured
with `crap -d 3000`, default memory settings for both programs, `LC_ALL=C`, and
output written to `/dev/null`. Times are means; memory is mean peak RSS reported
by `crap`.

- **1,000,000 lines, 125 MB:** msort **209 ms / 8.04 MB**, macOS `/usr/bin/sort`
  **297 ms / 181 MB** (15 and 11 runs, respectively).
- **6,001,215 lines, 754 MB:** msort **1.55 s / 8.26 MB**, macOS `/usr/bin/sort`
  **1.91 s / 1.10 GB** (3 runs each).

Both datasets produced identical output, checked byte for byte. These are short
local measurements; performance varies with the input and machine.

msort has a narrower feature set than Unix `sort`, so it has fewer cases and
compatibility details to handle. That simpler implementation can contribute to
the speed difference alongside SIMD; these measurements compare the overall
programs.

The input data comes from the [TPC-H](https://www.tpc.org/tpch/) `LINEITEM` table
at scale factor 1. Download the **TPC-H tools (DBGEN)** from the
[official TPC download page](https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp).
Build DBGEN following its included instructions, generate `LINEITEM` at scale
factor 1, and place `lineitem.tbl` in `data/`. The local files used above omit
the trailing `|` separator on each record. The smaller input is the first
1,000,000 lines:

```sh
head -n 1000000 data/lineitem.tbl > data/lineitem_1000000.tbl
```

To repeat with the local `crap` executable and datasets (neither is checked in):

```sh
make build
LC_ALL=C ./crap -d 3000 \
  './zig-out/bin/msort --parallel=1 -o=/dev/null data/lineitem_1000000.tbl' \
  '/usr/bin/sort --parallel=1 -o /dev/null data/lineitem_1000000.tbl'
```

Use `data/lineitem.tbl` for the larger dataset.
