// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./DIYTokenV2.sol";
import "./console.sol";

contract DIYTokenV3 is DIYTokenV2 {
    function initializeV3(
        string memory name,
        string memory symbol
    ) public  reinitializer(3) {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        console.log("Ran reinitializer");
    }
}
