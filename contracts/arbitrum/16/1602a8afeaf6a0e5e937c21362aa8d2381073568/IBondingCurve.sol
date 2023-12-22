// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ----------------------------------------------------------------------------
// IBindingCurve contract
// ----------------------------------------------------------------------------

interface IBondingCurve {
    function BondingCurveType() external view returns (string memory);

    // Processing logic must implemented in subclasses

    function calculateMintAmountFromBondingCurve(
        uint256 tokens,
        uint256 totalSupply,
        bytes memory parameters
    ) external view returns (uint256 x, uint256 y);

    function calculateBurnAmountFromBondingCurve(
        uint256 tokens,
        uint256 totalSupply,
        bytes memory parameters
    ) external view returns (uint256 x, uint256 y);

    function price(uint256 totalSupply, bytes memory parameters) external view returns (uint256 price);
}

