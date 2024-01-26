import re
import ast
import os
import json
import platform
import slitherin

from collections import namedtuple

from storage import Storage
from config import PLATFORM_DATA, SOLC_DIR


def get_slitherin_detectors() -> list:
    return [detector.ARGUMENT for detector in slitherin.plugin_detectors]

def get_solc_path(comp_ver):
    if comp_ver == None:
        return None
    if comp_ver[0] == 'v':
        comp_ver = comp_ver[1:]
    solc_ver = comp_ver
    if "-" in solc_ver:
        solc_ver = solc_ver.split("-")[0]

    solc_files = os.listdir(SOLC_DIR)
    for file in solc_files:
        if file.startswith(f"v{solc_ver}"):
            return os.path.join(SOLC_DIR, file)
    return None

def get_address(filename):
    m = re.match("^([0-9a-zA-Z]{40})_.*\.sol$", filename)
    if m:
        return "0x"+m.group(1)

Contract = namedtuple('Contract', 'address,chain_id,filename,compiler,detectors')
DETECTORS = get_slitherin_detectors()

def get_solc_dir():
    p = platform.system()
    solc_dir = os.path.join(SOLC_DIR, PLATFORM_DATA[platform.system()])
    if os.path.isdir(solc_dir):
        return solc_dir
    else:
        raise Exception(f"No solc directory in {SOLC_DIR} for platform {p}")

def get_contracts(dir_name, detectors, new_contracts = False, new_detectors = False, skip_duplicates = False, skip_libs = False, limit = None):
    #connect db if need
    storage = Storage()
    i = 0
    contracts_fname = os.path.join(dir_name, "contracts.json")
    if os.path.isfile(contracts_fname):
        with open(contracts_fname) as f:
            for line in f:
                contract_info = json.loads(line)
                if skip_duplicates and "similar" in contract_info:
                    continue #skip contracts that have similar contractsv
                if skip_libs and "lib" in contract_info:
                    continue #skip contracts that contain only lib files
                if new_contracts or new_detectors:
                    detectors_checked = storage.get_contract_detectors(contract_info["address"], contract_info["chain_id"])
                if new_contracts and len(detectors_checked) > 0:
                    continue #skip contracts checked by any detector
                if new_detectors:
                    detectors_to_check = [d for d in detectors if d not in detectors_checked]
                else:
                    detectors_to_check = detectors
                if len(detectors_to_check) == 0:
                    continue
                i += 1
                if limit is not None and i > limit:
                    return
                yield Contract(
                    contract_info["address"], contract_info["chain_id"],
                    os.path.join(dir_name, contract_info["address"][2:4], contract_info["address"][2:]), 
                    os.path.join(get_solc_dir(), contract_info["compiler"]),
                    detectors_to_check)
    elif os.path.isdir(dir_name):
        for project_name in os.listdir(dir_name):
            project_path = os.path.join(dir_name, project_name)
            if os.path.isdir(project_path) or project_path.endswith('.sol'):
                yield Contract("", "", project_path, os.path.join(get_solc_dir(), "v0.8.20+commit.a1b79de6"), detectors)

if __name__ == "__main__":
    folder_path = os.path.join("..", "detectors")
    argument_values = extract_detectors(folder_path)
    print("Unique ARGUMENT values:")
    for x in argument_values:
        #if 'reentrancy' in x[0]:
        print(x)

