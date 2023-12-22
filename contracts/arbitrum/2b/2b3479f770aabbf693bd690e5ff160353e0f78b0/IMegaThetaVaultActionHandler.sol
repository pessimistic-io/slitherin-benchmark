// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IThetaVaultActionHandler.sol";

interface IMegaThetaVaultActionHandler {
    function depositForOwner(address owner, uint168 tokenAmount, uint32 realTimeCVIValue) external returns (uint256 megaThetaTokensMinted);
    function withdrawForOwner(address owner, uint168 thetaTokenAmount, uint32 realTimeCVIValue) external returns (uint256 tokenWithdrawnAmount);
    function thetaVault() external view returns (IThetaVaultActionHandler);
}

