// SPDX-License-Identifier: MIT
pragma solidity  ^0.8.0;

interface IDataVault {
    function balance() external view returns (uint256);
    function tvl() external view returns (uint256);
    
}
