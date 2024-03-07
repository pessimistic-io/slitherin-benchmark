"""Loads verified contracts source code. 
"""
import json
import os
import click
import asyncio

from utils.etherscan import get_raw_source, contracts_to_object
from config import ETHERSCAN_QUERY_LIMIT

async def amain(output, input, chain_id):
    sem = asyncio.Semaphore(ETHERSCAN_QUERY_LIMIT)
    with open(input, 'r') as f:
        for line in f:
            contract_info = json.loads(line)
            contract_info["address"] = contract_info["address"].lower()
            full_dir = os.path.join(output, contract_info["address"][2:4], contract_info["address"][2:])
            if os.path.exists(full_dir):
                print(f"skip exits {contract_info['address']}")
                continue
            async with sem:  # semaphore limits num of simultaneous downloads
                print(f"get_raw_source {contract_info['address']}")
                raw = await get_raw_source(contract_info['address'], chain_id)
                if raw is None:
                    print(f"skip {contract_info['address']}")
                    continue
            response = contracts_to_object(raw)
            if response == 'ERROR_ZERO_LENGTH':
                print(f"skip ERROR_ZERO_LENGTH")
                continue
            with open(os.path.join(output, "contracts.json"), 'a+') as f_json:
                f_json.write(json.dumps({
                    "address": contract_info['address'],
                    "chain_id": chain_id,
                    "name": response["name"],
                    "compiler": response["compiler"]
                })+"\n")
            
            for contract_file in response["files"]:
                full_name = os.path.join(full_dir, contract_file["filename"])
                print(f"makedirs {full_name}")
                os.makedirs(os.path.dirname(full_name), exist_ok=True)
                with open(full_name, 'w') as f_sol:
                    f_sol.write(contract_file["source"])
        

@click.command()
@click.option('-o', '--output', help="directory to save results", required=True)
@click.option('-i', '--input', help="json file with contracts", required=True)
@click.option('-c', '--chain_id', help="hex chain id", required=True, type=str)
def main(output, input, chain_id):
    asyncio.run(amain(output, input, chain_id))

if __name__ == "__main__":
    main()
