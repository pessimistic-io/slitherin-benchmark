// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICapPool {
    function deposit ( uint256 amount ) external payable;
    function getCurrencyBalance ( address account ) external view returns ( uint256 );
    function withdraw ( uint256 currencyAmount ) external;
}

