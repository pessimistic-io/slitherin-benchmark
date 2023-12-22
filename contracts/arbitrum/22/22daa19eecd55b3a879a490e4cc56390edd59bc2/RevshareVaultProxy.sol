//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./CommonProxy.sol";

import "./IRevshareVault.sol";

contract RevshareVaultProxy is CommonProxy {

    constructor(address impl, bytes memory initData) CommonProxy("RevshareVault", impl, initData) {
        
    }
    
}
