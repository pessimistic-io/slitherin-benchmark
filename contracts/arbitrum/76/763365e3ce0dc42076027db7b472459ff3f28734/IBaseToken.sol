//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IBaseToken {
    function getIndexPrice(uint256 interval) external view returns (uint256);
}

