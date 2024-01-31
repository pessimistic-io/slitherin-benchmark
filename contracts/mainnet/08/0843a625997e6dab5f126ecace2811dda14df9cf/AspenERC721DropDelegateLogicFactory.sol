// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Clones.sol";
import "./Ownable.sol";
import "./IAspenDeployer.sol";
import "./AspenERC721DropDelegateLogic.sol";

contract AspenERC721DropDelegateLogicFactory is Ownable {
    /// ===============================================
    ///  ========== State variables - public ==========
    /// ===============================================
    AspenERC721DropDelegateLogic public implementation;

    constructor() {
        // Deploy the implementation contract and set implementationAddress
        implementation = new AspenERC721DropDelegateLogic();
        implementation.initialize();
    }

    function deploy() external onlyOwner returns (AspenERC721DropDelegateLogic newClone) {
        newClone = AspenERC721DropDelegateLogic(Clones.clone(address(implementation)));
        newClone.initialize();
    }
}

