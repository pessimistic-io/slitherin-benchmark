import re
import ast
import os
import json

from collections import namedtuple

SOLC_DIR = "solc-bin"

class AbstractDetector:
    pass  # Your AbstractDetector class definition here

def extract_detectors(folder_path):
    argument_values = set()
    for root, _, files in os.walk(folder_path):
        for file_name in files:
            if root.endswith("__") or file_name.startswith("__"):
                continue
            
            if file_name.endswith(".py"):
                file_path = os.path.join(root, file_name)
                module_path = os.path.splitext(os.path.relpath(file_path, folder_path))[0].replace(os.path.sep, ".")

                with open(file_path, "r") as file:
                    try:
                        tree = ast.parse(file.read(), filename=file_path)
                        for node in ast.walk(tree):
                            #print(node)
                            if isinstance(node, ast.ClassDef) and issubclass(AbstractDetector, globals().get(node.name, object)):
                                for class_node in node.body:
                                    #if (isinstance(class_node, ast.Assign)):
                                    #    print("CLASSNAME", class_node.targets[0])
                                    #print(class_node.name)
                                    if (
                                        isinstance(class_node, ast.Assign)
                                        and len(class_node.targets) == 1
                                        and isinstance(class_node.targets[0], ast.Name)
                                        and class_node.targets[0].id == "ARGUMENT"
                                        and isinstance(class_node.value, ast.Str)
                                    ):
                                        argument_values.add((module_path, class_node.value.s))
                    except SyntaxError as e:
                        print(f"Error parsing file {file_path}: {e}")

    return list(argument_values)

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

Contract = namedtuple('Contract', 'filename,compiler')

def get_contracts(dir_name, limit = None, solc_ver = None):
    i = 0
    with open(os.path.join(dir_name, "contracts.json")) as f:
        for line in f:
            if limit is not None and i>=limit:
                return
            contract_info = json.loads(line)
            i += 1
            yield Contract(os.path.join(dir_name, contract_info["address"][2:4], contract_info["address"][2:]), os.path.join(SOLC_DIR, contract_info["compiler"]))

if __name__ == "__main__":
    folder_path = os.path.join("..", "detectors")
    argument_values = extract_detectors(folder_path)
    print("Unique ARGUMENT values:")
    for x in argument_values:
        #if 'reentrancy' in x[0]:
        print(x)

