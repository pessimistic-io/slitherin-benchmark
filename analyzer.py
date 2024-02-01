import json
import os
import re
from collections import namedtuple

Finding = namedtuple('Finding', 'address, filename, lines')
class SlitherOutError(Exception):
    pass

def slither_analyzer(output:str) -> dict[list[Finding]]:
    # Return a dictionary with detector names as keys and True/False as values
    """Analyze slither json output.
    Args:
        output: slither output in json mode.
    Returns:
        dict with keys detectors names and values Findings.
    """
    result = {}
    if len(output)<6:
        raise SlitherOutError('empty output')
    output = json.loads(output, strict=False)
        
    if output['success'] and 'results' in output and 'detectors' in output['results']:
        for detector_result in output['results']['detectors']:
            findings = []
            for element in detector_result['elements']:
                path, fname = os.path.split(element['source_mapping']['filename_relative'])
                address = f"0x{path[-40:]}"
                if not re.match(r"[0-9]{40}", address):
                    address = path
                findings.append(Finding(address, fname, ",".join([str(l) for l in element['source_mapping']['lines']])))
            result[detector_result['check']] = findings
    elif not 'results' in output:
        raise SlitherOutError('no results')
    return result
