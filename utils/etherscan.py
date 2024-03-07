import aiohttp
import asyncio
import json
import re

from config import API_ENDPOINT_BY_CHAIN, API_KEY_BY_CHAIN
from utils.sol import clean_verification_date_header, transform_multiline_imports, clean_imports

async def get_raw_source(address:str, chain_id:str, retry:int = 3):
    """Function download contract from etherscan(or other chain scan)

    Args:
        address: Contract address.
        chain_id: hex chain id.

    Returns:
        Etherscan API query result
    """
    url = f"{API_ENDPOINT_BY_CHAIN[chain_id]}&address={address}&apikey={API_KEY_BY_CHAIN[chain_id]}"

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as resp:
                if resp.status == 200:
                    resp_json = await resp.json()
                    if "result" in resp_json and len(resp_json["result"]) > 0:
                        if isinstance(resp_json["result"], list):
                            return resp_json["result"][0]
                else:
                    print(f"retry status {resp.status}")
                    await asyncio.sleep(5)
                    if retry > 0:
                        return await get_raw_source(address, chain_id, retry-1) 
        return None
    except Exception as error:
        print(error)
        return None


def clean_weird_chars(input_str):
    # This covers only the case of a not imported contract,
    # where the three structure gets flattened (no filename duplicates).
    # Happened once in 800k contracts, it should not impact much.
    return re.sub(r'[^\x20-\x7E]', '', input_str)  # Keeps ASCII chars [32-126]

def contracts_to_object(source:str) -> dict:
    """Transform etherscan API response to dict structure.
    Flatten file names.
    Args:
        source (str): Etherscan API response.

    Returns:
        on success dict: Contract
        {
            'name': Contract name,
            'compiler': Solc version,
            'files': [
                {
                    'filename': flatten file name,
                    'source': Solidity code
                }
            ]
        }
        on error str
    """
    src, files_list = None, []
    
    # Around 99% of the sources are wrapped in {{}}, we need only a pair of {}
    try:
        if source['SourceCode'][:2] == "{{":
            source_code = source['SourceCode'][1:-1]
        else:
            source_code = source['SourceCode']
        src = json.loads(source_code)  # Parse JSON containing multiple files
    except json.JSONDecodeError:
        if 'SourceCode' in source and len(source['SourceCode']):
            return {
                "name": source.get("ContractName"), 
                "compiler": source.get("CompilerVersion"), 
                "files": [{
                    "filename": f"{source['ContractName']}.sol", 
                    "source": clean_verification_date_header(source['SourceCode'])
                }]
            }
        return "ERROR_ZERO_LENGTH"
    
    if src.get("language") and src["language"] != "Solidity":
        return ""
    
    root = src.get("sources", src)  # 99% of the sources are wrapped in .sources
    
    # Check if there are multiple contracts with the same name in different folders.
    # If so, don't flatten the folder structure. The folder structure gets flattened by default
    # to avoid many possible errors.
    duplicated_names = []
    buff = {}
    for k in root.keys():
        file_name = k.split("/")[-1]
        if file_name in buff:
            buff[file_name] += 1
            duplicated_names.append(k)
        else:
            buff[file_name] = 1
    
    real_files = {}
    depth_iter = -2
    while len(duplicated_names) > 0 and depth_iter > -10:
        next_duplicates = []
        for k in duplicated_names:
            file_path = k.split("/")
            upper_file_name = "_".join(file_path[depth_iter+1:])
            if upper_file_name in buff:
                del buff[upper_file_name]
            file_name = "_".join(file_path[depth_iter:])
            if file_name in buff:
                buff[file_name] += 1
                next_duplicates.append(k)
            else:
                buff[file_name] = 1
                real_files[k] = file_name
        
        depth_iter = depth_iter - 1
        duplicated_names = next_duplicates
        
    for k in root.keys():
        file_path = k.split("/")
        if k in real_files: # duplicate resolved
            file_name = real_files[k]
        else:
            file_name = file_path[-1]

        file_source = clean_verification_date_header(root[k]["content"])
        file_name = clean_weird_chars(file_name)
        file_source = transform_multiline_imports(file_source)
        file_source = clean_imports(file_source, real_files)  # Clean imports from path in source
        files_list.append({"filename": file_name, "source": file_source})
    return {"name": source.get("ContractName"), "compiler": source.get("CompilerVersion"), "files": files_list}

