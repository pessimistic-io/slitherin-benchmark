// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IKobe {
    function ethPair() external view returns (address);
    function usdtPair() external view returns (address);
    function isAddressWhitelisted(address _module) external view returns (bool);
    function buyFee() external view returns (uint256);
    function sellFee() external view returns (uint256);
    function forceSwapBack() external returns (bool);
}
