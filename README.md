# Slitherin Benchmark

The Slitherin Benchmark is designed for running detectors on Ethereum Virtual Machine (EVM) compatible Smart Contracts' verified sources database.

## Setup

### Configuration

1. Rename `example.config.py` to `config.py` and customize the parameters if needed.

### Databases

The benchmark comes with default databases for [Mainnet](https://github.com/pessimistic-io/slitherin-benchmark/tree/main/contracts/mainnet) and [Arbitrum](https://github.com/pessimistic-io/slitherin-benchmark/tree/main/contracts/arbitrum) contracts. The Mainnet database contains a random slice of verified contracts.

#### Database Directory Structure

Each database contains a `contracts.json` file with a JSON line for each contract. Each JSON must have the following fields: `address` (contract address), `chain_id` (blockchain ID in hex format, e.g., 0x1), and `compiler` (Solidity compiler version).

The source code of each contract is stored in `xx/address/`, where `xx` is the first two symbols in the hex representation of the address.

Use `loader.py` to load the source code of verified contracts from Etherscan. The input file should contain a JSON with the required field `address`.

```bash
python loader.py -o [output_directory] -i [input_json_file] -c [chain_id]
```
### Solc Compiler Loader
Load Solidity compiler binaries from ethereum/solc-bin.

```bash
python solc_loader.py
```
## Usage
```bash
python runner.py -o [output_file] -eo [extra_output_file] -i [contracts_directory] [other_options]
Options:

-o, --output: File to save results.
-eo, --extra-output: File to save extra results (address, detector name, lines).
-i, --input: Directory with contracts.
-nc, --new-contracts: Check only unchecked contracts.
-nd, --new-detectors: Check contracts only with unchecked detectors.
-t, --timeout: Stops benchmark after seconds.
-l, --limit: Stops benchmark after seconds.
-d, --detect: Comma-separated list of detectors (defaults to Slitherin detectors).
-p, --pool: Number of process pools (defaults to CPU count).
```

The runner uses SQLite to save information about which contracts were checked with which detectors. Use the --new-contracts and --new-detectors flags to skip already checked contracts.
