// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract AIFU is MintableBaseToken {
    constructor() public MintableBaseToken("Waifu AI", "$AIFU", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$AIFU";
    }
}

