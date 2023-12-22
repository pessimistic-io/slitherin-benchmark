// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";

struct TokenBalance {
    address addr;
    address holderAddress;
    string name;
    string symbol;
    uint8 decimals;
    uint256 balance;
    uint256 totalSupply;
}

struct TokenInfo {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 totalSupply;
}

contract TokenProvider is Initializable, OwnableUpgradeable {
    address[] public tokens;
    mapping(address => uint256) _tokensIndex;
    mapping(address => bool) _tokensExist;

    function initialize() public initializer {
        __Ownable_init();
    }

    /*function withdraw() public {
        require(owner == msg.sender);
        owner.transfer(address(this).balance);
    }*/

    function addToken(address addr) public virtual onlyOwner returns(bool) {
        if (_tokensExist[addr]) {
            return false;
        }
        _tokensIndex[addr] = tokens.length;
        _tokensExist[addr] = true;
        tokens.push(addr);
        return true;
    }

    function addTokens(address[] memory addrs) public virtual onlyOwner {
        for (uint256 i=0;i<addrs.length;i++){
            address addr = addrs[i];
            if (!_tokensExist[addr]) {
                _tokensIndex[addr] = tokens.length;
                _tokensExist[addr] = true;
                tokens.push(addr);
            }
        }
    }

    function removeToken(address addr) public virtual onlyOwner returns(bool) {
        if (!_tokensExist[addr]) {
            return false;
        }
        delete tokens[_tokensIndex[addr]];
        _tokensIndex[addr] = 0;
        _tokensExist[addr] = false;
        return true;
    }

    function removeTokens(address[] memory addrs) public virtual onlyOwner {
        for (uint256 i=0;i<addrs.length;i++) {
            address addr = addrs[i];
            if (_tokensExist[addr]) {
                delete tokens[_tokensIndex[addr]];
                _tokensIndex[addr] = 0;
                _tokensExist[addr] = false;
            }
        }
    }

    function getBalances(address addr) public virtual view returns(TokenBalance[] memory list) {
        list = new TokenBalance[](tokens.length);
        for(uint256 i=0;i < tokens.length;i++) {
            IERC20 t = IERC20(tokens[i]);
            IERC20Metadata m = IERC20Metadata(tokens[i]);

            TokenBalance memory tb = TokenBalance(tokens[i], addr, m.name(), m.symbol(), m.decimals(), t.balanceOf(addr), t.totalSupply());
            list[i] = tb;
        }
    }

    function getTokens() public virtual view returns(TokenInfo[] memory list) {
        list = new TokenInfo[](tokens.length);
        for(uint256 i=0;i < tokens.length;i++) {
            IERC20 t = IERC20(tokens[i]);
            IERC20Metadata m = IERC20Metadata(tokens[i]);

            TokenInfo memory ti = TokenInfo(tokens[i], m.name(), m.symbol(), m.decimals(), t.totalSupply());
            list[i] = ti;
        }
    }
}
