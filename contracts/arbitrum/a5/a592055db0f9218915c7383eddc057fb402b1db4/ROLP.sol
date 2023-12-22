// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MintableBaseToken.sol";

contract ROLP is MintableBaseToken {
    constructor() MintableBaseToken("Roseon LP", "ROLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "ROLP";
    }
}

