// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC20PresetMinterPauserUpgradeable} from "./ERC20PresetMinterPauserUpgradeable.sol";

contract Option42069Inu is ERC20PresetMinterPauserUpgradeable {

    constructor() public {
        super.initialize("Option 420 69 Inu", "OPTION42069INU");
        mint(msg.sender, 1000000e18);
    }

}
