// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract MLP is MintableBaseToken {
    constructor() public MintableBaseToken("MYC LP", "MLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "MLP";
    }
}

