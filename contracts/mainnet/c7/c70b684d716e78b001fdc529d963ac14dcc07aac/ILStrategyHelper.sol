// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./GPv2Order.sol";
import "./IVault.sol";
import "./LStrategy.sol";
import "./IUniV3Vault.sol";
import "./INonfungiblePositionManager.sol";

interface ILStrategyHelper {
    function checkOrder(
        GPv2Order.Data memory order,
        bytes calldata uuid,
        address erc20Vault,
        uint256 fee
    ) external;

    function getPreOrder(uint256[] memory tvl, uint256 minAmountOut) external view returns (LStrategy.PreOrder memory);

    function tickFromPriceX96(uint256 priceX96) external pure returns (int24);

    function calculateTokenAmounts(IUniV3Vault lowerVault, IUniV3Vault upperVault, IVault erc20Vault, uint256 amount0, uint256 amount1, INonfungiblePositionManager positionManager, bool isDeposit) external view returns (uint256[] memory lowerAmounts, uint256[] memory upperAmounts);
}

