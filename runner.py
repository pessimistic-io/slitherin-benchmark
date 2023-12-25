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

from utils import extract_detectors, get_contracts, Contract
from analyzer import slither_analyzer, SlitherOutError
DETECTORS = extract_detectors(os.path.join("..", "slitherin", "detectors"))

def process_file(contract: Contract, detectors: list = None) -> tuple[Contract, dict[str, list]]:
    """Run subproccess contract processing
    Args:
        contract: contract to analyze.
    Returns:
        Contract, detector name, list of findings.
    """
    if detectors is None:
        detectors = ['--pess']
    else:
        detectors = ['--detect', '.'.join(detectors)]
    try:
        # Run slitherin command and capture output
        # slitherin --pess tests/multiple_storage_read_test.sol --json -
        logger = logging.getLogger()
        command = ['slitherin', '--pess', contract.filename, '--json', '-']
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
            logger.exception("error analyzer filename %s output = _%s_ outlen=%d outlen_line1=%d out=_%s_", contract.filename, result.stdout, len(result.stdout), len(slitherin_out), result.stdout)
            return contract, {"error": []}
        # Return filename and detector results
        return contract, detector_results
    except subprocess.CalledProcessError as e:
        # Handle any errors that occur during slitherin execution
        logger.error("%s returned %s: %s", e.returncode, contract.filename, e.output)
        return contract, {'error': []}


@click.command()
@click.option('-o', '--output', help="file to save results", default=None)
@click.option('-eo', '--extra_output', help="file to save extra results(address, detector name, lines)", default=None)
@click.option('-i', '--input', help="directory with contracts")
@click.option('-t', '--timeout', help="stops benchmark after seconds", default=None, type=int)
@click.option('-l', '--limit', help="stops benchmark after seconds", default=None, type=int)
@click.option('-d', '--detect', help=f"Comma-separated list of detectors, defaults to slitherin detectors: %s" % ",".join(d[1] for d in DETECTORS), default=None, type=str)
@click.option('-p', '--pool', help="number of process pools, defaults to cpu count", default=os.cpu_count(), type=int)
def main(output, extra_output, input, timeout, limit, detect, pool):
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s: %(asctime)s - %(process)s - %(message)s"))

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    
    # Use multiprocessing Pool to run slitherin in parallel
    logger.info("starting pool on %d cores", pool)
    detector_statistics = Counter()
    start_time = time.time()
    if extra_output is not None:
        extra_result_lines = []
    else:
        extra_result_lines = None
    with Pool(pool) as pool:
        for contract, detector_results in pool.imap(partial(process_file, detectors=detect), get_contracts(input)):
            detector_statistics['total'] += 1
            for detector, findings in detector_results.items():
                detector_statistics[detector] += 1
                if extra_output is not None:
                    for finding in findings:
                        with open(extra_output, 'a+') as f_extra:
                            f_extra.write(f"{finding.address};{finding.filename};{detector};\"{finding.lines}\"\n")
            if limit is not None and detector_statistics['total'] >= limit:
                logger.info("limit stop, processed %d tasks", detector_statistics['total'])
                break
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

