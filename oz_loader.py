from collections import Counter
import os
import git
import json
import hashlib
import click
import os

OZ_DIR = "oz"
OZ_REPO = "https://github.com/OpenZeppelin/openzeppelin-contracts.git"

def get_oz_contracts(base_dir):
    file_hashes = []
    for fname in os.listdir(base_dir):
        if os.path.isdir(os.path.join(base_dir, fname)):
            file_hashes += get_oz_contracts(os.path.join(base_dir, fname))
        elif fname.endswith(".sol"):
            with open(os.path.join(base_dir, fname), 'r') as f:
                 file_hashes.append(hashlib.sha256(f.read().encode('utf-8').strip()).hexdigest())
    return file_hashes

def load_oz_hashes():
    if not os.path.isdir(OZ_DIR):
        os.mkdir(OZ_DIR)
    repo = git.Repo.clone_from(OZ_REPO, OZ_DIR)
    branch_list = [r.remote_head for r in repo.remote().refs]
    oz_hashes = []
    for branch in branch_list:
        repo.git.checkout(branch)
        oz_hashes += get_oz_contracts(os.path.join(OZ_DIR, "contracts"))
        print(f"branch {branch} hashes {len(oz_hashes)}")
    oz_hashes = list(set(oz_hashes))
    print(f"all branches hashes {len(oz_hashes)}")
    return oz_hashes

@click.command()
@click.option('-o', '--output', help="file to save hashes")
def main(output):
    oz_hashes = load_oz_hashes()
    print(oz_hashes)
    with open(output, 'w') as f:
        json.dump(oz_hashes, f)

if __name__ == "__main__":
    main()
