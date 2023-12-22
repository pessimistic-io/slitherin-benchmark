// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract UnityChain is MintableBaseToken {
    constructor() public MintableBaseToken("UnityChain", "$UNITY", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "$UNITY";
    }
}

