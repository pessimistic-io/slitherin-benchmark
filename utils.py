import ast
import os

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

def get_contracts(dir_name, limit = None):
    i = 0
    for file in os.listdir(dir_name):
        if limit is not None and i>=limit:
            break
        if os.path.isdir(os.path.join(dir_name,file)):
            for contract in get_contracts(os.path.join(dir_name, file), None if limit is None else limit - i):
                i += 1
                yield contract
        elif file.endswith(".sol"):
            i += 1
            yield os.path.join(dir_name, file)

if __name__ == "__main__":
    folder_path = os.path.join("..", "detectors")
    argument_values = extract_detectors(folder_path)
    print("Unique ARGUMENT values:")
    for x in argument_values:
        #if 'reentrancy' in x[0]:
        print(x)

