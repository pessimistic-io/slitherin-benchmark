// SPDX-License-Identifier: BUSL-1.1
// Reality NFT Contracts

pragma solidity ^0.8.9;

import "./IERC1155Upgradeable.sol";

/// @dev Required interface for Fractional NFT aggregate contract to be used by ERC20 adapters
/// Decimal value is to be understood as a fixed comma, 18 decimal positions, value representig fractional tokens
interface IRealityProperties is IERC1155Upgradeable {
    /// @dev Transfers fractional tokens
    function fractionalTransferByAdapter(address from, address to, uint256 decimalValue) external;

    /// @dev Returns total supply as full decimal value
    function fractionalTotalSupply(address erc20adapter) external view returns (uint256);

    /// @dev Returns address balance as full decimal value    
    function fractionalBalanceOf(address account, uint256 tokenId) external view returns (uint256);

    /// @dev Returns token id for the given adapter address
    function getTokenId(address erc20adapter) external view returns (uint256);
}
