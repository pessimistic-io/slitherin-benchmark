// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract EsLEX is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed LEX", "esLEX", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "esLEX";
    }
}

