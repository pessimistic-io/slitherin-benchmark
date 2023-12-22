// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITradeStorage {
   
    // ---------- owner setting part ----------
    function tradeVol(address _account, uint256 _day) external view returns (uint256);
    function swapVol(address _account, uint256 _day) external view returns (uint256);
    function totalTradeVol(uint256 _day) external view returns (uint256);
    function totalSwapVol(uint256 _day) external view returns (uint256);

    function updateTrade(address _account, uint256 _volUsd) external;
    function updateSwap(address _account, uint256 _volUsd) external;

}

