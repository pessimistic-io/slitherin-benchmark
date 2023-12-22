//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./CommonProxy.sol";

/**
 * Dexible proxy so we can upgrade the logic using multi-sig
 */
contract DexibleProxy is CommonProxy {

    constructor(address _impl, bytes memory initData) CommonProxy("DexibleProxy", _impl, initData) {

    }
    
}
