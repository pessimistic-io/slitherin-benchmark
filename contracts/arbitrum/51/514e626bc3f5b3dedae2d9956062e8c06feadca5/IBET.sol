// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./MintableBaseToken.sol";

contract IBET is MintableBaseToken {
    constructor() public MintableBaseToken("IBET", "IBET", 5_000_000_000 ether) {
    }

    function id() external pure returns (string memory _name) {
        return "IBET";
    }
}

