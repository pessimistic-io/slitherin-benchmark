
// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

pragma solidity ^0.7.1;

import {ReentrancyGuarded, Ownable, Strings, Address, SafeMath, Context} from "./Darwin721.sol";
import {ArrayUtils} from "./ArrayUtils.sol";


contract White is  ReentrancyGuarded, Ownable{

    using SafeMath for uint256;

    mapping(address => bool) internal _whiteMap;
    
    constructor() {
        
    }
    
    function version() public pure returns (uint){
        return 1;
    }

    function isWhite(address addr) public view  returns (bool) {
        return _whiteMap[addr];
    }

    function addWhites(address[] memory addrs) public onlyOwner{
        for(uint32 i=0; i<addrs.length; ++i){
            _whiteMap[addrs[i]] = true;
        }
    }
}


