// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";

contract Nft5 {
    address owner;
    uint256 s_variable = 123;
    uint256 s_otherVar = 0;

    bytes4 private constant FUNC_SELECTOR = bytes4(keccak256("doSomething()"));

    constructor() {
        owner = msg.sender;
    }

    function doSomething() public returns (bool) {
        s_variable = 123;
        s_otherVar = 2;
        return true;
    }

    function getFuncSelector() public pure returns (bytes4) {
        return FUNC_SELECTOR;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}

