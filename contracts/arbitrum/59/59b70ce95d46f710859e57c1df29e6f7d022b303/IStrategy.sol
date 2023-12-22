// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

interface IStrategy {
    function deposit(uint256 amount) external;
    function withdrawTo(address account, uint256 amount) external;
    function previewWithdrawGLP(uint256 amount) external view returns (uint256);
    function previewWithdrawLentAsset(uint256 amount) external view returns (uint256);
    function prepareWithdrawGLP(uint256 amount) external returns (uint256);
    function prepareWithdrawLendingAsset(uint256 amount) external returns (uint256);
    function balanceOfEquity() external view returns (uint256);
    function rebalance() external;
    function claimRewards() external;
    function claimAndRebalance() external;
}
