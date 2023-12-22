// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";

contract SupportedTokens is Ownable {

    mapping (address => bool) _supportedTokens;
    address[] _tokensList;

    error NotZeroAddress();

    constructor() Ownable(msg.sender) {
    }

    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert NotZeroAddress();
        require (!_supportedTokens[token], "Already Supported");
        _supportedTokens[token] = true;
        _tokensList.push(token);
    }

    function getTokensList() public view returns (address[] memory) {
        return _tokensList;
    }

    function isSupportedToken(address token) public view returns (bool) {
        return _supportedTokens[token];
    }

}
