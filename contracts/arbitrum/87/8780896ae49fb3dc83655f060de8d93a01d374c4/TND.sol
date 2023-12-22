// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract TND is MintableBaseToken {
    constructor() public MintableBaseToken("TND", "TND", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "TND";
    }
}

