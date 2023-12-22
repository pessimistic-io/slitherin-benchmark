// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

interface IZap {
    function zapInToken(address _from, uint256 amount, address _to) external;

    function zapIn(address _to) external payable;

    function zapOut(address _from, uint256 amount) external;
}

