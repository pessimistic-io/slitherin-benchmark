//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./PRBMathUD60x18.sol";

import "./AbstractAveraging.sol";

/// @title GeometricAveraging
/// @notice A strategy for calculating weighted averages using the geometric mean.
contract GeometricAveraging is AbstractAveraging {
    using PRBMathUD60x18 for uint256;

    /// @inheritdoc IAveragingStrategy
    /// @dev Zero values are replaced with one as the natural log of zero is undefined.
    function calculateWeightedValue(uint256 value, uint256 weight) external pure override returns (uint256) {
        if (value == 0) {
            // Natural log of 0 is undefined, so we use 1 as a substitute
            value = 1;
        }

        return value.fromUint().ln() * weight;
    }

    /// @inheritdoc IAveragingStrategy
    function calculateWeightedAverage(
        uint256 totalWeightedValues,
        uint256 totalWeight
    ) external pure override returns (uint256) {
        if (totalWeight == 0) {
            // Ambiguous result, so we revert
            revert TotalWeightCannotBeZero();
        }

        return (totalWeightedValues / totalWeight).exp().toUint();
    }
}

