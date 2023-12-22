// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20 } from "./ERC20_IERC20.sol";

interface IFCNVault is IERC20 {
    function asset() external view returns (address);

    function owner() external view returns (address);

    function fcnProduct() external view returns (address);

    function totalAssets() external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);

    function redeem(uint256 shares) external returns (uint256);
}

