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

contract TokenProviderV2 is Initializable, OwnableUpgradeable {
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
        (bool valid,,) = getERC20At(addr);
        if (!valid) {
            revert();
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
                (bool valid,,) = getERC20At(addr);
                if (!valid) {
                    continue;
                }
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
            (bool valid, IERC20 t, IERC20Metadata m) = getERC20At(tokens[i]);
            if (!valid) {
                continue;
            }

            TokenBalance memory tb = TokenBalance(tokens[i], addr, m.name(), m.symbol(), m.decimals(), t.balanceOf(addr), t.totalSupply());
            list[i] = tb;
        }
    }

    function getTokens() public virtual view returns(TokenInfo[] memory list) {
        list = new TokenInfo[](tokens.length);
        for(uint256 i=0;i < tokens.length;i++) {
            (bool valid, IERC20 t, IERC20Metadata m) = getERC20At(tokens[i]);
            if (!valid) {
                continue;
            }

            TokenInfo memory ti = TokenInfo(tokens[i], m.name(), m.symbol(), m.decimals(), t.totalSupply());
            list[i] = ti;
        }
    }

    function isContract(address _addr) private view returns (bool valid){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function countValidERC20(address[] memory _tokens) private view returns(uint256) {
        uint256 count = 0;
        for(uint256 i=0;i < _tokens.length;i++) {
            (bool valid, , ) = getERC20At(_tokens[i]);
            if (valid) {
                count++;
            }
        }
        return count;
    }

    function getERC20At(address _addr) private view returns (bool, IERC20, IERC20Metadata) {
        IERC20 t = IERC20(_addr);
        IERC20Metadata m = IERC20Metadata(_addr);

        if (!isContract(_addr)) {
            return (false, t, m);
        }

        try m.decimals() returns(uint8) {} catch{
            return (false, t, m);
        }
        return (true, t, m);
    }

    function fetchBalances(address addr, address[] memory _tokens) public virtual view returns(TokenBalance[] memory list) {
        uint256 count = countValidERC20(_tokens);
        list = new TokenBalance[](count);
        uint256 slot = 0;
        for(uint256 i=0;i < _tokens.length;i++) {
            (bool valid, IERC20 t, IERC20Metadata m) = getERC20At(_tokens[i]);
            if (!valid) {
                continue;
            }
            TokenBalance memory tb = TokenBalance(_tokens[i], addr, m.name(), m.symbol(), m.decimals(), t.balanceOf(addr), t.totalSupply());
            list[slot] = tb;
            slot++;
        }
    }

    function fetchTokens(address[] memory _tokens) public virtual view returns(TokenInfo[] memory list) {
        uint256 count = countValidERC20(_tokens);
        list = new TokenInfo[](count);
        uint256 slot = 0;
        for(uint256 i=0;i < _tokens.length;i++) {
            (bool valid, IERC20 t, IERC20Metadata m) = getERC20At(_tokens[i]);
            if (!valid) {
                continue;
            }
            TokenInfo memory ti = TokenInfo(_tokens[i], m.name(), m.symbol(), m.decimals(), t.totalSupply());
            list[slot] = ti;
            slot++;
        }
    }
}
