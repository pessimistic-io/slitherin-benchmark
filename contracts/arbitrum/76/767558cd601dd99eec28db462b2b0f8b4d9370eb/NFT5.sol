// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";

contract Nft5 {
    uint256 public s_variable = 123;
    uint256 public s_otherVar = 0;
    address owner;

    bytes4 private constant FUNC_SELECTOR = bytes4(keccak256(bytes("doSomething()")));

    constructor() {
        owner = msg.sender;
    }

    function doSomething() public {
        s_variable = 123;
        s_otherVar = 2;
    }

    function getFuncSelector() public pure returns (bytes4) {
        return FUNC_SELECTOR;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}

