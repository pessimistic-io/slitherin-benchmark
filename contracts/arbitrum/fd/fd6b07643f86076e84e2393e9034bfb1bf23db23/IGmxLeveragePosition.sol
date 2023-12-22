// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Council <council@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.7.6;

/// @title IUnis`wapV3LiquidityPosition Interface
/// @author Enzyme Council <security@enzyme.finance>
interface IGmxLeveragePosition {
    enum GmxLeveragePositionActions {
        CreateIncreasePosition,
        CreateDecreasePosition,
        RemoveCollateral
    }

    event PositionAdded(
        address _externalPosition,
        address collateral,
        address indexToken,
        bool isLong,
        bool isIncrease,
        uint256 size
    );

    event ExecutionFailed(
        address _externalPosition,
        address collateral,
        address indexToken,
        bool isLong,
        bool isIncrease,
        uint256 size
    );

    function getOpenPositionsCount() external view returns (uint256);

    function getDebtAssets() external returns (address[] memory, uint256[] memory);

    function getManagedAssets() external returns (address[] memory, uint256[] memory);

    function init(bytes memory) external;

    function receiveCallFromVault(bytes memory) external;
}

