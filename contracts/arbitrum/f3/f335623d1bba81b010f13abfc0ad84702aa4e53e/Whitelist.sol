// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./IWhitelist.sol";

contract Whitelist is IWhitelist, Ownable {
    mapping(address => uint256) public tokenIndices;
    address[] public tokens;

    function tokenCount() public view returns (uint256) {
        return tokens.length;
    }

    function getTokenIndex(address _token) public view returns (uint256, bool) {
        if (_token == address(0)) {
            return (0, false);
        }
        uint256 index = tokenIndices[_token];
        return (index, tokens.length > index ? tokens[index] == _token : false);
    }

    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "WL/IT"); // invalid token
        tokenIndices[_token] = tokens.length;
        emit TokenAdded(_token, tokens.length);
        tokens.push(_token);
    }

    function removeToken(address _token) external onlyOwner {
        emit TokenRemoved(_token, tokenIndices[_token]);
        delete tokens[tokenIndices[_token]];
        delete tokenIndices[_token];
    }
}
