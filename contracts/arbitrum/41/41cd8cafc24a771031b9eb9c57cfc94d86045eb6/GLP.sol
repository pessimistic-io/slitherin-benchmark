// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract GLP is MintableBaseToken {
    constructor() public MintableBaseToken("MMY LP", "MLP", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "MLP";
    }
}

