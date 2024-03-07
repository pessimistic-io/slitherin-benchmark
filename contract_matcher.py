import hashlib
import click
import os
import json
import difflib
from tqdm import tqdm

from config import OZ_HASHES_FILE, POPULAR_HASHES_FILE, SIMILAR_KOEFF_LINES, SIMILAR_KOEFF

from oz_loader import load_oz_hashes

CONTRACT_HASHES = {}
CONTRACTS_BY_HASH = {}

def get_hashes_from_file(fname:str) -> list[str]:
    with open(fname, 'r') as f:
        return json.load(f)

def preload_hashes() -> list[str]:
    """Loads hashes from files OZ_HASHES_FILE, POPULAR_HASHES_FILE.
    If OZ_HASHES_FILE doesn't exists loads all versions OZ libs from repo and counts hashes.
    """
    if os.path.isfile(OZ_HASHES_FILE):
        oz_hashes = get_hashes_from_file(OZ_HASHES_FILE)
    else:
        oz_hashes = load_oz_hashes()
        with open(OZ_HASHES_FILE, 'w') as f:
            json.dump(oz_hashes, f)
    if os.path.isfile(POPULAR_HASHES_FILE):
        return get_hashes_from_file(POPULAR_HASHES_FILE) + oz_hashes
    else:
        return oz_hashes

MOST_COMMON_HASHES = set(preload_hashes())

def get_hash(s):
    return hashlib.sha256(s.encode('utf-8').strip()).hexdigest()

def compare_sources(contract1, contract2):
    all_similar = True
    for source1 in contract1:
        have_similar = False
        for source2 in contract2:
            lines1 = source1.split('\n')
            lines2 = source2.split('\n')
            d = list(difflib.unified_diff(lines1, lines2, n=0))
            if len(d)/(len(lines1)+len(lines2)) < SIMILAR_KOEFF_LINES:
                have_similar = True
                break
        if not have_similar:
            all_similar = False
            break
    return all_similar


def preload_contracts(contracts_dir):
    for dir1 in os.listdir(contracts_dir):
        if not os.path.isdir(os.path.join(contracts_dir, dir1)):
            continue
        for address in os.listdir(os.path.join(contracts_dir, dir1)):
            hashes = []
            for fname in os.listdir(os.path.join(contracts_dir, dir1, address)):
                with open(os.path.join(contracts_dir, dir1, address, fname), 'r') as f:
                    chash = get_hash(f.read())
                hashes.append(chash)
                if chash in CONTRACTS_BY_HASH:
                    CONTRACTS_BY_HASH[chash].append(address)
                else:
                    CONTRACTS_BY_HASH[chash] = [address]
            CONTRACT_HASHES[address] = hashes

def find_similar_contract(contract_source_by_hash, contracts_dir):
    contract_addresses = []
    for chash in contract_source_by_hash:
        if chash in CONTRACTS_BY_HASH:
            contract_addresses += CONTRACTS_BY_HASH[chash]
    #contract_addresses contains list of contracts where at least one file equals one file on current contract
    #we already removed most common files and libs
    for address in list(set(contract_addresses)):
        match = 0
        for chash in CONTRACT_HASHES[address]:
            if chash in contract_source_by_hash:
                match += 1
        if match > 0 and match/len(CONTRACT_HASHES[address])>=SIMILAR_KOEFF:
            match2 = 0
            for chash in contract_source_by_hash:
                if chash in CONTRACT_HASHES[address]:
                    match2 += 1
            if match2 > 0 and match2/len(contract_source_by_hash) >=SIMILAR_KOEFF:
                if match/len(CONTRACT_HASHES[address]) > 0.99 and match2/len(contract_source_by_hash) > 0.99:
                    return address
                contract = []
                for fname in os.listdir(os.path.join(contracts_dir, address[0:2], address)):
                    with open(os.path.join(contracts_dir, address[0:2], address, fname)) as f:
                        source = f.read()
                        if get_hash(source) not in contract_source_by_hash:
                            contract.append(source)
                compare = compare_sources(contract, [contract_source_by_hash[chash] for chash in contract_source_by_hash if chash not in CONTRACT_HASHES[address]])
                if compare:
                    return address
    return False

def update_hashes(address, contract_hashes):
    for chash in contract_hashes:
        if chash in CONTRACTS_BY_HASH:
            CONTRACTS_BY_HASH[chash].append(address)
        else:
            CONTRACTS_BY_HASH[chash] = [address]
    CONTRACT_HASHES[address] = contract_hashes

def match_contract(contract_sources:list[str], contract_info:dict, contracts_dir:str):
    contract_source_by_hash = {}
    for source in contract_sources:
        chash = get_hash(source)
        if chash not in MOST_COMMON_HASHES:
            contract_source_by_hash[chash] = source
    if len(contract_source_by_hash) == 0:
        contract_info["lib"] = True
    else:
        address = find_similar_contract(contract_source_by_hash, contracts_dir)
        update_hashes(contract_info["address"][2:], contract_source_by_hash)
        if address != False:
            contract_info["similar"] = "0x"+address
    return contract_info

@click.command()
@click.option('-i', '--input', help="directory with contracts")
def main(input):
    contracts_fname = os.path.join(input, "contracts.json")
    updated_contracts = []
    with open(contracts_fname) as f:
        for line in tqdm(f.readlines()):
            contract_info = json.loads(line)
            full_dir_name = os.path.join(input, contract_info["address"][2:4], contract_info["address"][2:])
            contract_sources = []
            for fname in os.listdir(full_dir_name):
                with open(os.path.join(full_dir_name, fname), 'r') as f:
                    contract_sources.append(f.read())
            contract_info = match_contract(contract_sources, contract_info, input)
            updated_contracts.append(json.dumps(contract_info))
    with open(contracts_fname, 'w') as f:
        for line in updated_contracts:
            f.write(line+"\n")

if __name__ == "__main__":
    main()
