// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISwapper {
    error TokenPairIsNotSupported(address tokenFrom, address tokenTo);
    function swapReceiveExact(address tokenFrom, address tokenTo, uint256 amount, uint256 maxSpendAmount) external returns (uint256) ;
    function swapSendExact(address tokenFrom, address tokenTo, uint256 amount, uint256 minReceiveAmount) external returns (uint256) ;
    function getPrice(address tokenFrom, address tokenTo, uint128 amount) view external returns (uint128);
} 
