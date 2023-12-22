// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILeverageStrategyView {
    function vaultManager() external view returns (address);

    function positionId() external view returns (uint256);

    function asset() external view returns (address);

    function debtToken() external view returns (address);

    function assetPool() external view returns (address);

    function debtPool() external view returns (address);

    function assetBalance() external view returns (uint256);

    function debtBalance() external view returns (uint256);

    function owner() external view returns (address);

    function addLeverage(uint256 amount, uint256 debt, bytes calldata data) external;

    function removeLeverage(uint256 amount, bytes calldata data) external;

    function closeLeverage(uint256 amount, bytes calldata data) external;

    function supply(uint256 withdraw) external;

    function borrow(uint256 debt) external;

    function repay(uint256 amount) external;

    function withdraw(uint256 withdraw) external;

    function switchAsset(address newAsset, uint256 amount, bytes calldata data) external;

    function switchDebt(address newDebtToken, uint256 newDebt, bytes calldata data) external;

    function version() external returns (string memory);

    function claimRewards() external;

    function claimRewardsSupply(uint256 amountOutMinimum) external;

    function claimRewardsRepay(uint256 amountOutMinimum) external;

    function upgradeToAndCall(address newImplementation, bytes memory data) external;

    function upgradeTo(address newImplementation) external;
}

