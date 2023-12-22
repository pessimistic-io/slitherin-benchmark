// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./Ownable.sol";

contract Whitelist is Ownable {
    mapping(address => bool) private whitelist;

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
    }

    function removeFromWhitelist(address _address) public onlyOwner {
        whitelist[_address] = false;
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }
}
