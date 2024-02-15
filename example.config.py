import logging

API_ENDPOINT_BY_CHAIN = {
    '0x1': 'https://api.etherscan.io/api?module=contract&action=getsourcecode',
    '0xA4B1': 'https://api.arbiscan.io/api?module=contract&action=getsourcecode', #arbitrum
}
API_KEY_BY_CHAIN = {
    '0x1': '',
    '0xA4B1': '', #arbitrum
}
ETHERSCAN_QUERY_LIMIT = 5

#github auth token, if None use github without auth.
GITHUB_TOKEN = None
#directory to store solc binaries
SOLC_DIR = "solc-bin"
#solc platforms supported
PLATFORM_DATA = {
    'Darwin': 'macosx-amd64',
    'Linux': 'linux-amd64'
}

LOGGING_LEVEL = logging.DEBUG
