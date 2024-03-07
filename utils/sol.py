import os
import re

def transform_multiline_imports(source):
    # Find all import statements with multiline curly braces
    matches = re.findall(r'import\s*({\s*[^}]*\s*}\s*from\s*)', source)

    # Iterate through matches and replace newlines in curly braces
    for import_block in matches:
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
            if len(full_path) == 0:
                cleaned_source += f"{line}\n"
            else:
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

def count_sol_files(dir_name:str) -> int:
    c = 0
    for fname in os.listdir(dir_name):
        full_fname = os.path.join(dir_name,fname)
        if os.path.isdir(full_fname):
            c += count_sol_files(full_fname)
        elif fname.endswith(".sol"):
            c += 1
    return c

