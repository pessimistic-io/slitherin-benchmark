// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract LEX is MintableBaseToken {
    constructor() public MintableBaseToken("LEX", "LEX", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "LEX";
    }
}

