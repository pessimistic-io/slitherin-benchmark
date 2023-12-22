// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract EsUNITY is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed Unity", "$esUNITY", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$esUNITY";
    }
}

