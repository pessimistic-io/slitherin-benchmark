// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract ULP is MintableBaseToken {
    constructor() public MintableBaseToken("$ULP", "$ULP", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$ULP";
    }
}

