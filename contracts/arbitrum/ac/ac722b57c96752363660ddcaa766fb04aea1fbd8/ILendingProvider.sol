/**
 * Interface for a lending provider
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILendingProvider {
    function supplyToMarket(
        bytes32 clientId,
        address asset,
        uint256 amount,
        bytes calldata extraArgs
    ) external;

    function withdrawFromMarket(
        bytes32 clientId,
        address underlyingAsset,
        uint256 amount,
        bytes calldata extraArgs
    ) external;

    function harvestMarketInterest(
        bytes32 clientId,
        address asset,
        bytes calldata extraArgs
    ) external;

    function borrowFromMarket(
        bytes32 clientId,
        address tokenToBorrow,
        uint256 amount,
        bytes calldata extraArgs
    ) external;

    function repayToMarket(
        bytes32 clientId,
        address positionToRepay,
        uint256 amount,
        bytes calldata extraArgs
    ) external;

    function getSupportedReserves(
        bytes32 clientId
    ) external view returns (address[] memory);

    function getReserveToken(
        bytes32 clientId,
        address underlyingToken
    ) external view returns (address reserveToken);

    function getPositionBalance(
        bytes32 clientId,
        address underlyingToken
    ) external view returns (uint256 marketBalance);
}

