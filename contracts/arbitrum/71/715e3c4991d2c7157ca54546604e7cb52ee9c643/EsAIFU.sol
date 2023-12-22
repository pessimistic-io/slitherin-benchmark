// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract EsAIFU is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed AIFU", "$esAIFU", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$esAIFU";
    }
}

