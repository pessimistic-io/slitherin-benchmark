// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IInvestor {
    function asset() external view returns (address);
    function lastGain() external view returns (uint256);
    function supplyIndex() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function borrowIndex() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function getUtilization() external view returns (uint256);
    function getSupplyRate(uint256) external view returns (uint256);
    function getBorrowRate(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function life(uint256) external view returns (uint256);
    function positions(uint256) external view returns (address, address, uint256, uint256, uint256);
    function earn(address, uint256, uint256) external returns (uint256);
    function sell(uint256, uint256, uint256) external;
    function save(uint256, uint256) external;
}

