// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract EsGMX is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed MMY", "esMMY", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "esMMY";
    }
}

