// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { GlobalACL, Auth, VESTER } from "./Auth.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ERC20 } from "./tokens_ERC20.sol";
import { ARB } from "./constants.sol";

contract ArbVault is GlobalACL {
    using SafeTransferLib for ERC20;

    constructor(Auth _auth) GlobalACL(_auth) { }

    function vestArb(address account, uint256 amount) external onlyRole(VESTER) {
        ERC20(ARB).safeTransfer(account, amount);
    }

    function transferToken(ERC20 token, address account, uint256 amount) external onlyConfigurator {
        token.safeTransfer(account, amount);
    }
}

