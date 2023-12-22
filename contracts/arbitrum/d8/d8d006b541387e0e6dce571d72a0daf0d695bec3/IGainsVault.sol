// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IGainsVault {
    function asset() external view returns (address);

    // Returns the global id of the current spoch.
    function currentEpoch() external view returns (uint256);

    // Returns the start timestamp of the current epoch.
    function currentEpochStart() external view returns (uint256);

    function maxDeposit(address owner) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    // Returns the epochs time(date) of the next withdraw
    // Base value [3, 2, 1]
    function withdrawEpochsTimelock() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    // DAI deposit function to Gains network
    function deposit(uint256 assets, address receiver) external returns (uint256);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function shareToAssetsPrice() external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);

    function makeWithdrawRequest(uint256 shares, address owner) external;

    // TODO: Check this feature is need
    function cancelWithdrawRequest(uint shares, address owner, uint unlockEpoch) external;
}

