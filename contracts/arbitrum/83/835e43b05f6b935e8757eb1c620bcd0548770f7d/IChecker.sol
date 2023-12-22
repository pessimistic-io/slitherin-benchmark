// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IChecker {
    function isFurionToken(address _tokenAddress) external view returns (bool);

    function addToken(address _tokenAddress) external;
}

