// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract EsTND is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed TND", "esTND", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "esTND";
    }
}

