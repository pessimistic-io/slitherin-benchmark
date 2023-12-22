// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// Interface for a USDC smart vault, which has permissioned deposit
// and withdraw functions and is only meant to interact with one
// address. Used by Sphere Finance to earn yield on the USDC minted
// from the PSM.
// Deposit and withdraw functions must be onlyPSM.
interface ISmartVault {
    function depositAndInvest(uint256 amount) external;

    function totalSupply() external view returns (uint256 amount);

    function previewWithdraw(
        uint256 amount
    ) external view returns (uint256 shares);

    function withdraw(uint256 shares) external;

    function underlying() external view returns (address);
}

