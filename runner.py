import os
import time
import subprocess
import logging
from multiprocessing import Pool
from collections import Counter
import pandas as pd
import click
from datetime import timedelta
from functools import partial

from utils import DETECTORS, get_contracts, Contract, count_sol_files
from analyzer import slither_analyzer, SlitherOutError
from storage import Storage
from config import LOGGING_LEVEL

CONTRACT_STAT_TYPE_NAME = 'by_contract'
FINDING_STAT_TYPE_NAME = 'by_finding'

def process_file(contract: Contract, use_slither: bool = False) -> tuple[Contract, dict[str, list]]:
    """Run subproccess contract processing
    Args:
        contract: contract to analyze.
    Returns:
        Contract, detector name, list of findings.
    """
    try:
        # Run slitherin command and capture output
        # slitherin --pess tests/multiple_storage_read_test.sol --json -
        logger = logging.getLogger()
        command = ['slither' if use_slither else 'slitherin', '--fail-none', '--detect', ','.join(contract.detectors), contract.filename, '--json', '-']
        if contract.compiler is not None:
            command.append("--solc")
            command.append(contract.compiler)
        logger.debug(" ".join(command))
        result = subprocess.run(command, capture_output=True, text=True, check=True, encoding="utf8")
        
        # Process the output using slitherAnalyzer function
        try:
            slitherin_out = result.stdout.split('\n')[0]
            detector_results = slither_analyzer(slitherin_out)
        except SlitherOutError as e:
            logger.error("SlitherOutError(%s) during command: %s" % (e.args[0], " ".join(command)))
            return contract, {'error': []} #TODO decide if we need e.args[0] message?
        except Exception as e:
            logger.exception("error analyzer filename %s output = _%s_ outlen=%d outlen_line1=%d", contract.filename, result.stdout, len(result.stdout), len(slitherin_out))
            return contract, {"error": []}
        # Return filename and detector results
        return contract, detector_results
    except subprocess.CalledProcessError as e:
        # Handle any errors that occur during slitherin execution
        logger.error("%s returned %s", e.returncode, contract.filename)
        return contract, {'error': []}


@click.command()
@click.option('-o', '--output', help="file to save results", default=None)
@click.option('-eo', '--extra-output', help="file to save extra results(address, detector name, lines)", default=None)
@click.option('-i', '--input', help="directory with contracts")
@click.option('-sd', '--skip-duplicates', is_flag=True, default=False, help="skip duplicate contracts(marked by contract_matcher).")
@click.option('-sl', '--skip-libs', is_flag=True, default=False, help="skip lib contracts(marked by contract_matcher).")
@click.option('-nc', '--new-contracts', is_flag=True, default=False, help="check only unchecked contracts.")
@click.option('-nd', '--new-detectors', is_flag=True, default=False, help="check contracts only with unchecked detectors.")
@click.option('-us', '--use-slither', is_flag=True, default=False, help="use slither instead of slitherin")
@click.option('-t', '--timeout', help="stops benchmark after seconds", default=None, type=int)
@click.option('-l', '--limit', help="stops benchmark after seconds", default=None, type=int)
@click.option('-d', '--detect', help=f"Comma-separated list of detectors, defaults to slitherin detectors: %s" % ",".join(DETECTORS), default=None, type=str)
@click.option('-p', '--pool', help="number of process pools, defaults to cpu count", default=os.cpu_count(), type=int)
def main(output, extra_output, input, skip_duplicates, skip_libs, new_contracts, new_detectors, use_slither, timeout, limit, detect, pool):
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s: %(asctime)s - %(process)s - %(message)s"))

    logger = logging.getLogger()
    logger.setLevel(LOGGING_LEVEL)
    logger.addHandler(handler)
    # Check params
    if detect is not None:
        detectors = detect.split(',')
    else:
        detectors = DETECTORS
    # Use multiprocessing Pool to run slitherin in parallel
    logger.info("starting pool on %d cores contract", pool)
    detector_statistics = { CONTRACT_STAT_TYPE_NAME: Counter(), FINDING_STAT_TYPE_NAME: Counter() }
    start_time = time.time()
    storage = Storage()
    with Pool(pool) as pool:
        for contract, detector_results in pool.imap(
            partial(process_file, use_slither=use_slither), get_contracts(input, detectors, new_contracts, new_detectors, skip_duplicates, skip_libs, limit)):
            count_files = (contract.address == "") #Not real contract, we check dir with files. Count stats by file.
            for detector, findings in detector_results.items():
                increment = 1
                if extra_output is not None or count_files:
                    files_counter = Counter()
                    for finding in findings:
                        files_counter[f"{finding.address}{finding.filename}"] += 1
                        if extra_output is not None:
                            with open(extra_output, 'a+') as f_extra:
                                f_extra.write(f"{finding.address};{finding.filename};{detector};\"{finding.lines}\"\n")
                        if count_files:
                            increment = len(files_counter)
                detector_statistics[CONTRACT_STAT_TYPE_NAME][detector] += increment
                detector_statistics[FINDING_STAT_TYPE_NAME][detector] += len(findings)
            sol_files = count_sol_files(contract.filename)
            for stat_type in detector_statistics:
                if count_files:
                    detector_statistics[stat_type]['files'] += sol_files
                else:
                    detector_statistics[stat_type]['contracts'] += 1

            for detector in contract.detectors:
                storage.set_contract_checked(contract.address, contract.chain_id, detector)
                
            if timeout is not None and time.time() - start_time > timeout:
                logger.info("timeout stop, processed %d tasks", detector_statistics['total'])
                break
    logger.info("completed pool in %s", str(timedelta(seconds=round(time.time()-start_time))))
    df = pd.DataFrame.from_dict(detector_statistics, orient='index')
    print(df.to_markdown())
    if output is not None:
        logger.info("Save stats to file %s", output)
        with open(output, 'w') as f:
            f.write(df.to_csv(sep=';'))     
    
if __name__ == "__main__":
    main()

