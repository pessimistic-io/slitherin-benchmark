import json
import re
import os
import click
import asyncio

from scan import get_raw_source
from config import ETHERSCAN_QUERY_LIMIT

CHAIN_ID = "0x1"

def transform_multiline_imports(source):
    # Find all import statements with multiline curly braces
    matches = re.findall(r'import\s*({\s*[^}]*\s*})', source)

    # Iterate through matches and replace newlines in curly braces
    for import_block in matches:
        print("MATCH", import_block)
        modified_import_block = import_block.replace("\n", ' ')
        source = source.replace(import_block, modified_import_block)

    return source
    
def clean_verification_date_header(source):
    if "Submitted for verification at " in source[:70]:
        index = source.find("*/")
        if index != -1:
            ret = source[index + 2:]
            while ret[:2] == "\r\n":
                ret = ret[2:]  # remove leading newlines
            return ret
    return source

def clean_weird_chars(input_str):
    # This covers only the case of a not imported contract,
    # where the three structure gets flattened (no filename duplicates).
    # Happened once in 800k contracts, it should not impact much.
    return re.sub(r'[^\x20-\x7E]', '', input_str)  # Keeps ASCII chars [32-126]

def count_matching_elements_from_end(list1, list2):
    # Iterate over the lists from the end
    i = len(list1) - 1
    j = len(list2) - 1
    count = 0

    while i >= 0 and j >= 0:
        if list1[i] == list2[j]:
            count += 1
        else:
            break  # Stop the loop if elements are not equal

        i -= 1
        j -= 1
    return count

def clean_imports(source:str, real_files:dict = None):
    """Flatting imports
     Args:
        source: Solidity source.
        real_files: keys are full path from etherscan, values are flatten

    Returns:
        Cleaned source.
    """
    cleaned_source = ''
    import_patt = 'import '
    break_chars = ["\"", "\\", "/"]
    break_chars_full_path = ["'", '"', ' ']
    lines = source.split('\n')
    
    for line in lines:
        if line.strip().startswith(import_patt):
            p1 = line.rfind(".sol")
            file_name = ".sol"
            full_path = []
            for i in range(p1 - 1, 0, -1):
                c = line[i]
                if c in break_chars:
                    full_path.insert(0, file_name)
                    file_name = ""
                    continue
                elif c in break_chars_full_path:
                    full_path.insert(0, file_name)
                    break
                file_name = c + file_name
            file_name = full_path[-1]
            full_path = [p for p in full_path if p != '.' and p != '..']
            if real_files is not None:
                max_score = 0
                for real_path, real_name in real_files.items():
                    real_path = real_path.split('/')
                    score = count_matching_elements_from_end(real_path, full_path)
                    if score > max_score:
                        max_score = score
                        file_name = real_name

            if ' from ' in line:
                pre = line.split(" from ")[0]
                cleaned_source += f"{pre} from \"./{file_name}\";\n"
            else:
                cleaned_source += f"import \"./{file_name}\";\n"
        else:
            cleaned_source += f"{line}\n"
    
    return cleaned_source


def contracts_to_object(source):
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

async def amain(output, input):
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
                raw = await get_raw_source(contract_info['address'], CHAIN_ID)
            response = contracts_to_object(raw)
            with open(os.path.join(output, "contracts.json"), 'a+') as f_json:
                f_json.write(json.dumps({
                    "address": contract_info['address'],
                    "chain_id": CHAIN_ID,
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
def main(output, input):
    asyncio.run(amain(output, input))

if __name__ == "__main__":
    main()
