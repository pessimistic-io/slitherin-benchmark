// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface ID2HelperBase {
    function addLiquidityD2Native(uint256 d2Amount) external payable returns (bool);
    function addLiquidityD2Sdr() external returns (bool);
    function buyRsd() external payable returns (bool);
    function buySdr() external returns (bool);
    function checkAndPerformArbitrage() external returns (bool);
    function kickBack() external payable;
    function pairD2Eth() external view returns (address);
    function pairD2Sdr() external view returns (address);
    function queryD2AmountFromSdr() external view returns (uint256);
    function queryD2Rate() external view returns (uint256);
    function queryPoolAddress() external view returns (address);
    function setD2(address d2TokenAddress) external;
}

