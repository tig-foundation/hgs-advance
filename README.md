# HGS Advance

This repository contains `hgs_advance`, a Rust implementation of an "advanced" and scalable Hybrid Genetic Search (HGS) for the Vehicle Routing Problem with Time Windows (VRPTW) and the Capacitated Vehicle Routing Problem (CVRP).

The algorithm was created by Thibaut Vidal (© 2026) as an advance submission for The Innovation Game (TIG) `vehicle_routing` challenge (Unique Algorithm Identifier: `c002_a110`). **This repository is the standalone distribution of that algorithm for use outside of the TIG game**: it compiles into a binary that can be run directly on vehicle routing instances defined in text files, under the license terms described [below](#license).

## Building

Requirements: a recent [Rust toolchain](https://rustup.rs).

```bash
cargo build --release
```

The solver binary is produced at `target/release/hgs_advance`.

## Running on Benchmark Instances

The `instances/` folder contains classical academic benchmark instances; the download scripts below fetch the full sets from [CVRPLIB](https://galgos.inf.puc-rio.br/cvrplib/en/).

**VRPTW** (`instances/vrptw/`): Solomon instances (100 customers, e.g. `R101`, `C101`, `RC201`) and large-scale Gehring & Homberger instances (200-1000 customers, e.g. `C1_2_1`, `RC2_10_5`):

```bash
instances/vrptw/download.sh            # Solomon set (56 instances, 100 customers)
instances/vrptw/download.sh 200        # Gehring & Homberger 200-customer set (60 instances)
instances/vrptw/download.sh all        # Solomon set + all Gehring & Homberger sizes
```

The sources are 7-Zip archives, so a `7z`/`7za` (p7zip) or `bsdtar` (libarchive) extractor is required.

**CVRP** (`instances/cvrp/`): the 100 "X" instances of Uchoa et al. (100-1000 customers, e.g. `X-n1001-k43`):

```bash
instances/cvrp/download.sh             # full X set (100 instances)
```

Usage:

```bash
./target/release/hgs_advance <FORMAT> <INSTANCE_FILE> [-o SOLUTION_FILE] [--hyperparameters JSON] [--seed BYTE]
```

where `FORMAT` is `vrptw` (Solomon / Gehring–Homberger text format) or `cvrp` (CVRPLIB/TSPLIB format). Examples:

```bash
# Solve a Solomon VRPTW instance and write the solution to RC101.sol
./target/release/hgs_advance vrptw instances/vrptw/RC101.txt -o RC101.sol

# Deeper search: higher exploration level (0 = fastest, 6 = deepest)
./target/release/hgs_advance cvrp instances/cvrp/X-n1001-k43.vrp \
    --hyperparameters '{"exploration_level": 6}' --seed 42
```

To run every instance in a folder, use `run_all.sh`. It runs `JOBS` instances in parallel (default: all CPU cores; the solver is single-threaded), writes a `.sol` and `.log` file per instance into the output folder, and collects a `summary.csv` with the cost, route count, runtime, and exit code of each run. Any extra arguments are passed through to the solver:

```bash
./run_all.sh vrptw instances/vrptw results/solomon
JOBS=4 ./run_all.sh cvrp instances/cvrp results/x --hyperparameters '{"exploration_level": 6}'
```

Notes:

- **Distance conventions.** For `vrptw`, coordinates and times are multiplied by 10 and Euclidean distances truncated, following the common convention for Solomon instances: reported costs are 10x the values found in the literature (e.g., a cost of `16313` on `RC101` corresponds to `1631.3`). For `cvrp`, distances are rounded to the nearest integer, as in the CVRPLIB X benchmark.
- **Hyperparameters.** `--hyperparameters` accepts a JSON object that can override any field of `Params` (see `src/params.rs`). The main knob is `exploration_level` (0-6), which loads a preset; any other keys are applied on top of that preset. Add `"display_traces": true` to print search traces during the run.
- **Solution files.** With `-o`, the best solution found is written in the standard `Route #k: ...` format, followed by `Cost`, `NB_ROUTES`, and `CPU_TIME` lines.



## Algorithm Description

The method builds on the HGS family of algorithms, as exemplified by the open-source [HGS-CVRP](https://github.com/vidalt/HGS-CVRP) implementation and the TIG baseline `[hgs_v1](https://github.com/tig-foundation/tig-monorepo/tree/main/tig-algorithms/src/vehicle_routing/hgs_v1)`. HGS is highly effective because it combines population-based exploration with aggressive local-search education. However, this same strength becomes a bottleneck on large instances: offspring are repeatedly improved through expensive full-dimensional local searches, and the population may spend substantial effort refining regions of the search space where many route structures are already stable.

`hgs_advance` targets this scalability bottleneck through three coordinated mechanisms:

1. **Evolutionary consensus compression.**
  The algorithm detects predecessor-successor relations that remain stable across successive feasible individuals in the population. These stable arcs are used to compress chains of clients into equivalent macro-clients, while preserving the demand, travel, service-time, and time-window information needed for valid CVRP/VRPTW evaluation.
2. **Reverse-mode decomposition.**
  Instead of maintaining a full master-level population throughout the run, the algorithm follows a single global incumbent trajectory. This master solution is decomposed into spatially coherent route-cluster subproblems, which are solved with HGS at increasing exploration depth and then reintegrated into the master solution. This moves population-based search to smaller and more focused subproblems.
3. **High-performance local search for large instances.**
  The local-search engine combines customer-level best-move selection, systematic lower-bound prefilters, route/customer timestamps to avoid redundant evaluations, inherited-route handling, and a bounded first-loop deterioration mechanism for controlled diversification.

Together, these components define a scalable HGS architecture in which consensus compression reduces the active problem size, reverse mode reduces the active search region, and the local-search engine reduces wasted move evaluations. These mechanisms are synergistic and interact throughout the run: the master solution induces high-quality seed solutions for the route-cluster subproblems; these seeds are deliberately inserted later to preserve early subproblem diversity; and, even before insertion, they participate in the consensus process to ensure that compression decisions are consistent with the inherited master structure. The implementation preserves the core strengths of HGS while making the method better suited to large-scale CVRP/VRPTW instances under limited computational budgets.

## Implementation Map

The main advance-specific components are implemented in the following files under `src/`:

- `solver.rs`: top-level entry point and mode selection. It dispatches to reverse mode when `params.decomp_nb_phases > 0`; otherwise, it runs the standard HGS flow.
- `genetic.rs`: main HGS loop, including crossover, education, repair, compression triggers, population remapping, and decompression of final solutions.
- `population.rs`: feasible and infeasible subpopulation management, diversity tracking, penalty adaptation, and evolutionary consensus tracking. This also includes consensus checks that account for the reserved delayed seed in subproblem runs.
- `compression.rs`: consensus-chain contraction into compact instances. It builds macro-clients from stable predecessor-successor chains while preserving demand, travel, service-time, and time-window semantics.
- `reverse_mode.rs`: reverse-mode decomposition workflow. It builds route-cluster subproblems from the master solution, maps clients between master and subproblem indices, runs phased subproblem HGS, merges subproblem routes, and applies master-level local search and repair.
- `local_search.rs`: high-performance local-search engine, including customer-level best-move selection, lower-bound move prefilters, route/customer timestamps, inherited-route handling, and bounded first-loop deterioration.
- `params.rs`: parameter definitions and presets controlling exploration level, compression cadence, decomposition phases, local-search behavior, and scalability-oriented options.

Additional support files include `sequence.rs`, `individual.rs`, and `problem.rs`, which provide route evaluation, individual representation, problem data, and CVRP/VRPTW feasibility machinery used by the advance-specific components. `main.rs` provides the command-line binary, and `loader_vrptw.rs`/`loader_cvrp.rs` parse Solomon-format and CVRPLIB-format benchmark instance files.

## Academic Papers

[1] Vidal, T., Crainic, T. G., Gendreau, M., and Prins, C. (2013). *A hybrid genetic algorithm with adaptive diversity management for a large class of vehicle routing problems with time windows*. Computers & Operations Research, 40(1), 475-489. [https://doi.org/10.1016/j.cor.2012.07.018](https://doi.org/10.1016/j.cor.2012.07.018)

[2] Vidal, T. (2022). *Hybrid genetic search for the CVRP: Open-source implementation and SWAP* neighborhood*. Computers & Operations Research, 140, 105643. [https://doi.org/10.1016/j.cor.2021.105643](https://doi.org/10.1016/j.cor.2021.105643)

## License

This code is available for use outside of the TIG game under the *[TIG Open Data License](LICENSE.md)* ([PDF](open_data_license.pdf)), subject to its share-alike and open data terms.

For users who do not wish to comply with those terms, this code is also available under the *[TIG Commercial License](commercial_license.pdf)*, subject to payment of the applicable commercial license fee.