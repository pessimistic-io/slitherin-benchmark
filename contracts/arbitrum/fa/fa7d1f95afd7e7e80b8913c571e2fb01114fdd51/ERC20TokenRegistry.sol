// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IERC20TokenRegistry.sol";

contract ERC20TokenRegistry is Ownable, IERC20TokenRegistry {
    mapping(address => bool) public tokenRegistry;
    mapping(address => uint256) public tokenLimits;

    constructor(address[] memory initialTokenSet) {
        for (uint16 index = 0; index < initialTokenSet.length; index++) {
            tokenRegistry[initialTokenSet[index]] = true;
        }
    }

    function addToken(address erc20Token) external onlyOwner {
        require(tokenRegistry[erc20Token] == false, "Token is already added");
        tokenRegistry[erc20Token] = true;
    }

    function removeToken(address erc20Token) external onlyOwner {
        require(tokenRegistry[erc20Token] == true, "Token is not in the list");
        tokenRegistry[erc20Token] = false;
    }

    function tokenInRegistry(address erc20Token) public view returns (bool) {
        if (tokenRegistry[erc20Token] || erc20Token == address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function setTokenLimit(address _token, uint256 _tokenLimit)
        external
        onlyOwner
    {
        require(tokenInRegistry(_token) == true, "No token in registry");
        tokenLimits[_token] = _tokenLimit;
    }

    function getTokenLimit(address _token) public view returns (uint256) {
        return tokenLimits[_token];
    }
}

