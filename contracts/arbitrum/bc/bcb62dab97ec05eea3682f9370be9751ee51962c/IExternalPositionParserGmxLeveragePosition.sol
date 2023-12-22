// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;

/// @title IExternalPositionParserUniswapV3LiquidityPosition Interface
/// @author Enzyme Council <security@enzyme.finance>
interface IExternalPositionParserGmxLeveragePosition {
    function parseAssetsForAction(
        address _externalPosition,
        uint256 _actionId,
        bytes memory _encodedActionArgs
    )
        external
        view
        returns (
            address[] memory assetsToTransfer_,
            uint256[] memory amountsToTransfer_,
            address[] memory assetsToReceive_
        );

    function parseInitArgs(
        address _vaultProxy,
        bytes memory _initializationData
    ) external returns (bytes memory initArgs_);
}

