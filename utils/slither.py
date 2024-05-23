import re
import subprocess
import json
import os
import re
from collections import namedtuple

Finding = namedtuple('Finding', 'address, filename, lines, description')
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
            description = detector_result['description'].strip()
            for i, element in enumerate(detector_result['elements']):
                path, fname = os.path.split(element['source_mapping']['filename_relative'])
                address = f"0x{path[-40:]}"
                if not re.match(r"[0-9]{40}", address):
                    address = path
                findings.append(Finding(address, fname, ",".join([str(l) for l in element['source_mapping']['lines']]), description if i == 0 else ''))
            if detector_result['check'] in result:
                result[detector_result['check']] += findings
            else:    
                result[detector_result['check']] = findings
    elif not 'results' in output:
        raise SlitherOutError('no results')
    return result

def escape_ansi(line):
    ansi_escape =re.compile(r'(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]')
    return ansi_escape.sub('', line)

def parse_ascii_table(ascii_table: str):
    header = []
    data = []
    for line in ascii_table.split('\n'):
      line = escape_ansi(line)
      if '-+-' in line: continue
      cells = list(filter(lambda x: x!='|', line.split('|')))
      striped_cells = list(map(lambda c: c.strip(), cells))
      if not header:
        header = striped_cells
        continue
      data.append(striped_cells)
    
    return header, data

def get_slitherin_detectors() -> list:
    try:
        import slitherin
        return [x.ARGUMENT for x in slitherin.plugin_detectors]
    except ModuleNotFoundError:
        return get_slitherin_detectors_from_slither()

def get_slitherin_detectors_from_slither() -> list:
    try:
        command = ['slither', '--list-detectors']
        result = subprocess.run(command, capture_output=True, text=True, check=True, encoding="utf8")
        header, detectors = parse_ascii_table(result.stdout)
        return [d[2] for d in detectors if len(d)>2 and d[2].startswith('pess-')]
    except subprocess.CalledProcessError as e:
        print(e)
        return []

