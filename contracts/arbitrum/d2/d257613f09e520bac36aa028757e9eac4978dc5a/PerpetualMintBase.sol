// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { ERC165Base } from "./ERC165Base.sol";
import { ERC1155Base } from "./ERC1155Base.sol";

import { ERC1155MetadataExtension } from "./ERC1155MetadataExtension.sol";
import { IPerpetualMintBase } from "./IPerpetualMintBase.sol";
import { PerpetualMintInternal } from "./PerpetualMintInternal.sol";

/// @title PerpetualMintBase
/// @dev PerpetualMintBase facet containing all protocol-specific externally called functions
contract PerpetualMintBase is
    ERC1155Base,
    ERC1155MetadataExtension,
    ERC165Base,
    IPerpetualMintBase,
    PerpetualMintInternal
{
    constructor(address vrf) PerpetualMintInternal(vrf) {}

    /// @inheritdoc IPerpetualMintBase
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @notice Chainlink VRF Coordinator callback
    /// @param requestId id of request for random values
    /// @param randomWords random values returned from Chainlink VRF coordination
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        _fulfillRandomWords(requestId, randomWords);
    }
}

