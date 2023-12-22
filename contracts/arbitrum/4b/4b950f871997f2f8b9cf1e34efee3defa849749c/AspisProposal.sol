pragma solidity 0.8.10;


abstract contract AspisProposal {
    // bytes4 constant internal PROPOSAL_CHANGE_FUNDRAISING_TARGET = 0x97edceef;
    // bytes4 constant internal PROPOSAL_CHANGE_FUNDRAISING_START_TIME = 0x5b41dfee;
    // bytes4 constant internal PROPOSAL_CHANGE_FUNDRAISING_FINISH_TIME = 0x11bdc357;
    // bytes4 constant internal PROPOSAL_CHANGE_VOTING_CONFIG = 0xbecbd871;
    // bytes4 constant internal PROPOSAL_CHANGE_ABILITY_TO_CHANGE_MANAGER = 0x44548363;
    bytes4 constant internal PROPOSAL_UPDATE_MANAGER = 0x58aba00f;
    // bytes4 constant internal PROPOSAL_ADD_SUPPORTED_TOKENS = 0x8c7ac746;
    // bytes4 constant internal PROPOSAL_REMOVE_SUPPORTED_TOKENS = 0x8a448c59;
    // bytes4 constant internal PROPOSAL_ADD_WALLETS = 0x7f649783;
    // bytes4 constant internal PROPOSAL_REMOVE_WALLETS = 0x548db174;
    // bytes4 constant internal PROPOSAL_ADD_PROTOCOLS = 0xac76a31c;
    bytes4 constant internal PROPOSAL_REMOVE_PROTOCOLS = 0x89ca0027;
    // bytes4 constant internal PROPOSAL_CHANGE_INITIAL_TOKEN_PRICE = 0x3f55306f;
    // bytes4 constant internal PROPOSAL_CHANGE_DEPOSIT_LIMITS = 0xd91cd644;
    // bytes4 constant internal PROPOSAL_CHANGE_WITHDRAWL_WINDOWS = 0x7b7b2105;
    // bytes4 constant internal PROPOSAL_CHANGE_LOCKUP_PERIOD = 0xa32bdee9;
    // bytes4 constant internal PROPOSAL_CHANGE_RAGE_QUIT_FEE = 0xb272a7e9;
    // bytes4 constant internal PROPOSAL_CHANGE_FUND_MANAGEMENT_FEE = 0x183bb2c1;
    // bytes4 constant internal PROPOSAL_CHANGE_PERFORMANCE_FEE = 0x70897b23;
    // bytes4 constant internal PROPOSAL_CHANGE_ENTRANCE_FEE = 0xfe56f5a0;
    // bytes4 constant internal PROPOSAL_DIRECT_ASSET_TRANSFER = 0x21feab07;
    // bytes4 constant internal PROPOSAL_ADD_DEFI_PROTOCOL = 0x30fb7402;
    // bytes4 constant internal PROPOSAL_REMOVE_DEFI_PROTOCOL = 0x520aa6fa;
    bytes4 constant internal PROPOSAL_MINT= 0x40c10f19;
    bytes4 constant internal PROPOSAL_BURN= 0x9dc29fac;
    bytes4 constant internal PROPOSAL_REMOVE_TRADING_TOKENS = 0xe8efe397;
}
