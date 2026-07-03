use anyhow::{anyhow, Result};
use clap::{arg, value_parser, Command};
use hgs_advance::Solver;
use serde_json::{Map, Value};
use std::path::PathBuf;
use std::time::Instant;

fn cli() -> Command {
    Command::new("hgs_advance")
        .about("Hybrid Genetic Search (hgs_advance) for CVRP and VRPTW benchmark instances")
        .arg(
            arg!(<FORMAT> "Instance format: 'vrptw' (Solomon / Gehring-Homberger) or 'cvrp' (CVRPLIB / TSPLIB)")
                .value_parser(["vrptw", "cvrp"]),
        )
        .arg(arg!(<INSTANCE_FILE> "Path to the instance file").value_parser(value_parser!(PathBuf)))
        .arg(
            arg!(-o --output [SOLUTION_FILE] "Path to write the best solution found")
                .value_parser(value_parser!(PathBuf)),
        )
        .arg(
            arg!(--hyperparameters [JSON] "JSON object of solver hyperparameters, e.g. '{\"exploration_level\": 5}'")
                .value_parser(value_parser!(String)),
        )
        .arg(arg!(--seed [SEED] "Random seed byte (0-255)").value_parser(value_parser!(u8)))
}

fn main() -> Result<()> {
    let matches = cli().get_matches();
    let format = matches.get_one::<String>("FORMAT").unwrap();
    let instance_file = matches.get_one::<PathBuf>("INSTANCE_FILE").unwrap();
    let output = matches.get_one::<PathBuf>("output");
    let seed = matches.get_one::<u8>("seed").copied();
    let hyperparameters: Option<Map<String, Value>> = matches
        .get_one::<String>("hyperparameters")
        .map(|s| serde_json::from_str(s))
        .transpose()
        .map_err(|e| anyhow!("Invalid --hyperparameters JSON: {}", e))?;

    anyhow::ensure!(
        instance_file.exists(),
        "Instance file does not exist: {}",
        instance_file.display()
    );

    let t0 = Instant::now();
    let result = Solver::solve_benchmark_instance(
        format,
        instance_file
            .to_str()
            .ok_or_else(|| anyhow!("Invalid instance path"))?,
        &hyperparameters,
        output.and_then(|p| p.to_str()),
        seed,
    )?;

    match result {
        Some((_solution, cost, nb_routes)) => {
            println!("Instance:  {}", instance_file.display());
            println!("Cost:      {}", cost);
            println!("Routes:    {}", nb_routes);
            println!("Time:      {:.2}s", t0.elapsed().as_secs_f64());
            if let Some(out) = output {
                println!("Solution written to {}", out.display());
            }
            Ok(())
        }
        None => Err(anyhow!("No feasible solution found")),
    }
}
