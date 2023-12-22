// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IWaterLendingHandler {    

    function getAssetsAddresses(address _longToken, address _shortToken) external view returns (address, address);
    function borrow(uint256 _amount, uint256 _leverage, address _longToken) external returns (uint256, uint256);
    function getUtilizationRate(address _waterVault) external view returns (uint256);
}

