import os
import time
import requests
import re
import logging
from urllib.parse import quote

from config import GITHUB_TOKEN, SOLC_DIR, PLATFORM_DATA

base_url = "https://github.com/ethereum/solc-bin/blob/gh-pages/"

def get_github_headers():
    if GITHUB_TOKEN is None:
        return None
    else:
        return {"Authorization": f"Bearer {GITHUB_TOKEN}", "X-GitHub-Api-Version": "2022-11-28"}
    
def main():
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s: %(asctime)s - %(process)s - %(message)s"))
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    logger.addHandler(handler)

    for k, v in PLATFORM_DATA.items():
        try:  
            os.mkdir(os.path.join(SOLC_DIR, v))
        except OSError as error:
            pass
        check_solc_release(k, v)

def check_solc_release(platform, gh_folder):
    logger = logging.getLogger()
    # get last parsed commit from the local directory
    old_commit = get_last_solc_commit(os.path.join(SOLC_DIR, PLATFORM_DATA[platform]))
    logger.info("last commit %s", old_commit)
    # get all commits newer than the last parsed one or download all commits if the .last_commit file doesn't exist
    new_commits = get_new_commits(old_commit if old_commit else None, gh_folder)
    if not new_commits:
        logger.info("No new commit for platform %s", platform)
        return
    
    # for each commit, download the new uploaded files
    for nc in new_commits:
        logger.info("Processing new commit %s %s", nc['sha'], nc['commit']['message'])
        download_uploaded_files(platform, nc['url'])
        time.sleep(5)
    print("processed %d commits" % len(new_commits))
    # update last commit in the local directory
    last_commit_hash = new_commits[-1]['sha']
    update_last_solc_commit(last_commit_hash, os.path.join(SOLC_DIR, PLATFORM_DATA[platform]))

def get_last_solc_commit(folder_path):
    last_commit_file = os.path.join(folder_path, ".last_commit")
    if os.path.exists(last_commit_file):
        with open(last_commit_file, 'r') as f:
            return f.read().strip()
    return None

def update_last_solc_commit(commit_hash, folder_path):
    last_commit_file = os.path.join(folder_path, ".last_commit")
    with open(last_commit_file, 'w') as f:
        f.write(commit_hash)

def get_new_commits(old_commit, folder_path):
    username = 'ethereum'
    repo_name = 'solc-bin'
    last_sha = None
    new_commits = []
    found_old = False
    while not found_old:
        api_url = f"https://api.github.com/repos/{username}/{repo_name}/commits?path={folder_path}"
        if last_sha is not None:
            api_url += f"&sha={last_sha}"
        try:
            resp = requests.get(api_url, headers=get_github_headers())
        except Exception as e:
            print(str(e))
            return []

        resp_json = resp.json()
        print("got %d commits" % len(resp_json))
        if last_sha is not None:
            resp_json = resp_json[1:] #Skip first commit, it is already processed
        if len(resp_json) == 0:
            break
        
        for commit in resp_json:
            last_sha = commit['sha']
            if old_commit is None or commit['sha'] != old_commit:
                new_commits.insert(0, commit)  # inserts at the beginning of the array so that we have the oldest first
            elif old_commit is not None:
                found_old = True
                break

    return new_commits

def download_uploaded_files(platform, commit_url):
    logger = logging.getLogger()
    parent_folder = PLATFORM_DATA[platform]
    files_resp = requests.get(commit_url + "?per_page=50", headers=get_github_headers())
    resp_json = files_resp.json()
    if not 'files' in resp_json:
        print("No files found", resp_json)
        time.sleep(150)
        return download_uploaded_files(platform, commit_url)
    added_files = [e for e in resp_json['files'] if
                   e['filename'][:len(parent_folder)] == parent_folder and 'latest' not in e['filename']]
    
    for file in added_files:
        p = file['filename'].split("/")
        fn = p[-1] if len(p) > 1 else file['filename']

        if fn in ['list.js', 'list.json', 'list.txt']:  # gave up the map filter
            continue
        m = re.search(r'v\d+\.\d+\.\d+\+commit\.[a-zA-Z0-9]+$', file['filename'])
        if not m:
            logger.info(f"file format not parsed, skip {file['filename']}")
            continue
        local_path = os.path.join(SOLC_DIR, parent_folder, m.group(0))
        logger.info("download local path %s", local_path)
        if file['status'] == "modified":  # binary updated
            delete_file(local_path)

        try:
            if not os.path.exists(local_path):
                download_file(base_url + quote(file['filename']) + "?raw=true", local_path)
                logger.info("Downloaded " + local_path)
        except Exception as err:
            logger.exception(str(err))

def delete_file(filepath):
    if os.path.exists(filepath):
        os.unlink(filepath)

def download_file(file_url, output_location_path):
    with open(output_location_path, 'wb') as writer:
        response = requests.get(file_url, stream=True)
        for chunk in response.iter_content(chunk_size=128):
            writer.write(chunk)
    os.chmod(output_location_path , 0o777)
if __name__ == "__main__":
    main()

