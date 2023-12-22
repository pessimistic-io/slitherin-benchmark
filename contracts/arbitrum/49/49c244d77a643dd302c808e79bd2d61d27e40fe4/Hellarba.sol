// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.7;
 
contract Hellarba {
    
    string hello="hello arbitrum";
    function getData() public view returns (string memory) 
    {
        return hello;
    }
    
}