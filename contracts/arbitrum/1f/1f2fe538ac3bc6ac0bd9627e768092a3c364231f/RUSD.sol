// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MintableBaseToken.sol";

contract RUSD is MintableBaseToken {
    constructor() MintableBaseToken("Roseon USD", "RUSD", 0) {}

    function id() external pure returns (string memory _name) {
        return "RUSD";
    }
}

