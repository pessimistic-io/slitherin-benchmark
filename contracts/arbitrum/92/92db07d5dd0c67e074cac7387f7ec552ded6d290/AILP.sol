// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract AILP is MintableBaseToken {
    constructor() public MintableBaseToken("$AILP", "$AILP", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$AILP";
    }
}

