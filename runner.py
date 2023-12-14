import os
import json
import time
import subprocess
import logging
from multiprocessing import Pool
from collections import Counter
import pandas as pd
import click
from datetime import timedelta

from utils import extract_detectors, get_contracts, Contract
DETECTORS = extract_detectors(os.path.join("..", "slitherin", "detectors"))

def slitherAnalyzer(output):
    # Return a dictionary with detector names as keys and True/False as values
    result = {}
    if len(output)<6:
        return {'empty output': True}
    output = json.loads(output, strict=False)
        
    if output['success'] and 'results' in output and 'detectors' in output['results']:
        for detector_result in output['results']['detectors']:          
            result[detector_result['check']] = True
    else:
        return {'error': True}
    return result

def process_file(contract: Contract):
    try:
        # Run slitherin command and capture output
        # slitherin --pess tests/multiple_storage_read_test.sol --json -
        logger = logging.getLogger()
        command = ['slitherin', '--pess', contract.filename, '--json', '-']
        logger.debug(" ".join(command))
        if contract.compiler is not None:
            command.append("--solc")
            command.append(contract.compiler)
        result = subprocess.run(command, capture_output=True, text=True, check=True, encoding="utf8")
        
        # Process the output using slitherAnalyzer function
        try:
            slitherin_out = result.stdout.split('\n')[0]
            detector_results = slitherAnalyzer(slitherin_out)
        except Exception as e:
            logger.exception("error analyzer filename %s output = _%s_ outlen=%d outlen_line1=%d out=_%s_", filename, result.stdout, len(result.stdout), len(slitherin_out), result.stdout)
            return contract.filename, {"failed": True}
        # Return filename and detector results
        return contract.filename, detector_results
    except subprocess.CalledProcessError as e:
        # Handle any errors that occur during slitherin execution
        logger.error("%s returned %s: %s", e.returncode, contract.filename, e.output)
        return contract.filename, {'error': True}

@click.command()
@click.option('-o', '--output', help="file to save results", default=None)
@click.option('-i', '--input', help="directory with contracts")
@click.option('-t', '--timeout', help="stops benchmark after seconds", default=None, type=int)
def main(output, input, timeout):
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s: %(asctime)s - %(process)s - %(message)s"))

    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    logger.addHandler(handler)
    
    # Use multiprocessing Pool to run slitherin in parallel
    logger.info("starting pool on %d cores", os.cpu_count())
    detector_statistics = Counter()
    start_time = time.time()
    with Pool() as pool:
        for _, detector_results in pool.imap(process_file, get_contracts(input)):
            detector_statistics['total'] += 1
            for detector, found in detector_results.items():
                if found:
                    detector_statistics[detector] += 1
            if timeout is not None and time.time() - start_time > timeout:
                logger.info("timeout stop, processed %d tasks", detector_statistics['total'])
                break
    logger.info("completed pool in %s", str(timedelta(seconds=round(time.time()-start_time))))
    df = pd.DataFrame.from_dict(detector_statistics, orient='index')
    print(df.to_markdown())
    if output is not None:
        logger.info("Save stats to file %s", output)
        with open(output, 'w') as f:
            f.write(df.to_csv())    	
    
if __name__ == "__main__":
    main()

