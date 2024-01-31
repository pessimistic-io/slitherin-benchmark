// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Clones.sol";
import "./Ownable.sol";
import "./IAspenDeployer.sol";
import "./AspenERC1155DropDelegateLogic.sol";

contract AspenERC1155DropDelegateLogicFactory is Ownable {
    /// ===============================================
    ///  ========== State variables - public ==========
    /// ===============================================
    AspenERC1155DropDelegateLogic public implementation;

    constructor() {
        // Deploy the implementation contract and set implementationAddress
        implementation = new AspenERC1155DropDelegateLogic();

        implementation.initialize();
    }

    function deploy() external onlyOwner returns (AspenERC1155DropDelegateLogic newClone) {
        newClone = AspenERC1155DropDelegateLogic(Clones.clone(address(implementation)));
        newClone.initialize();
    }
}

