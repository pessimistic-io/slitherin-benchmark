// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library Commands {
    // Command Types. Maximum supported command at this moment is 255.

    // Command Types where value<20, executed in the first nested-if block
    uint8 constant DISTRIBUTE_ERC20_AMOUNTS = 3;
    uint8 constant DISTRIBUTE_ERC20_SHARES = 4;
    uint8 constant WRAP_AND_DISTRIBUTE_ERC20_AMOUNTS = 5;
    uint8 constant UNWRAP_NATIVE = 6;
    uint8 constant SWAP_UNISWAPV2_POOL = 10;

    // Command Types where 20<=value<24, executed in the second nested-if block
    uint8 constant SWAP_ZENLINK_STABLESWAP = 20;
}

