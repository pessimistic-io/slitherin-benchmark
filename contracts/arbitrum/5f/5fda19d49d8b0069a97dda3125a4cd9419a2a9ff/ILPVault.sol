//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Interfaces
import {IERC20} from "./IERC20.sol";

interface ILPVault is IERC20 {
    function underlying() external returns (IERC20);
    function mint(uint256 _shares, address _receiver) external returns (uint256);
    function burn(address _account, uint256 _shares) external;
    function previewDeposit(uint256 _assets) external view returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
}

