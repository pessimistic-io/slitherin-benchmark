// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { IERC165Base } from "./IERC165Base.sol";
import { IERC1155Base } from "./IERC1155Base.sol";

import { IERC1155MetadataExtension } from "./IERC1155MetadataExtension.sol";

/// @title IPerpetualMintBase
/// @dev Interface of the PerpetualMintBase facet
interface IPerpetualMintBase is
    IERC1155Base,
    IERC1155MetadataExtension,
    IERC165Base
{
    /// @notice Validates receipt of an ERC1155 transfer.
    /// @param operator Executor of transfer.
    /// @param from Sender of tokens.
    /// @param id Token ID received.
    /// @param value Quantity of tokens received.
    /// @param data Data payload.
    /// @return bytes4 Function's own selector if transfer is accepted.
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure returns (bytes4);
}

