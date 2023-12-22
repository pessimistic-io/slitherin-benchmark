// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "./ERC20.sol";

contract LessonTenHelperToken is ERC20 {
    uint256 public AMOUNT_TO_MINT = 1e18;

    constructor() ERC20("LessonTenHelperToken", "LTHT") {}

    function mint() external {
        _mint(msg.sender, AMOUNT_TO_MINT);
    }
}

