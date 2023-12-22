// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract XLP is MintableBaseToken {
    constructor() public MintableBaseToken("LEX LP", "XLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "XLP";
    }
}

