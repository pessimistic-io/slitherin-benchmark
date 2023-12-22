// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

interface IZap {
    function zapOut(address _from, uint amount, address _ROUTER) external;
    function zapIn(address _to, address _ROUTER) external payable;
    function zapInToken(address _from, uint amount, address _to, address _ROUTER) external;
}

