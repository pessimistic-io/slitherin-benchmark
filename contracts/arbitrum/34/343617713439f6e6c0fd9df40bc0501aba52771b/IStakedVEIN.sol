// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IStakedVEIN {
    //previewredeem
    function previewRedeem(uint256 shares) external view returns (uint256);
    //transfer
    function transfer(address recipient_, uint256 amount_) external returns (bool);
    //previewMint
    function previewMint(uint256 shares) external view returns (uint256);
    //transferFrom
    function transferFrom(address sender_, address recipient_, uint256 amount_) external returns (bool);
}
