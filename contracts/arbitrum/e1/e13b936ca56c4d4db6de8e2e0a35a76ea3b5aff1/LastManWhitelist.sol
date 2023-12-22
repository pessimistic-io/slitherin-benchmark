// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import { Ownable } from "./Ownable.sol";

contract LastManWhitelist is Ownable {

    bool whitelistOpen = true; // Set to true when deploy contract

    mapping(address => bool) public whitelistAddress;

    function whitelistClose() external onlyOwner {
      whitelistOpen = false;
    }

    function signUpToWhitelist() external {
        require(whitelistOpen == true, "Whitelist has closed");
        require(whitelistAddress[msg.sender] = false);
        whitelistAddress[msg.sender] = true;
    }

    function signOthersToWhitelist(address _address) external {
        require(whitelistOpen == true, "Whitelist has closed");
        require(whitelistAddress[_address] = false);
        whitelistAddress[_address] = true;
    }
}

