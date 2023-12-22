// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IWETH9} from "./IWETH9.sol";

struct RouterParameters {
    address weth9;
    address ezswapV2;
}

/// @title Router Immutable Storage contract
/// @notice Used along with the `RouterParameters` struct for ease of cross-chain deployment
contract RouterImmutables {
    /// @dev WETH9 address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IWETH9 internal immutable WETH9;


    // @dev EZV2 address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable EZSWAPV2; 

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(RouterParameters memory params) {
        WETH9 = IWETH9(params.weth9);
        EZSWAPV2 = params.ezswapV2;
    }
}

