// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

contract Checker is Ownable {
    // Separate pool factory
    address public spFactory;

    mapping(address => bool) private isFurion;

    modifier callable() {
        require(
            msg.sender == owner() || msg.sender == spFactory,
            "Checker: Not permitted to call."
        );
        _;
    }

    function isFurionToken(address _tokenAddress) public view returns (bool) {
        return isFurion[_tokenAddress];
    }

    function setSPFactory(address _spFactory) external onlyOwner {
        spFactory = _spFactory;
    }

    function addToken(address _tokenAddress) external callable {
        isFurion[_tokenAddress] = true;
    }
}

