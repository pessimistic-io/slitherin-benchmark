// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IV2Contract {
    
    function Migrate(
        address token,
        address beneficiary ,address creator,uint amount,uint endDate,uint8 feeRate, int priceInUSD, uint target,bool[] memory features)
         external payable;
         

}

