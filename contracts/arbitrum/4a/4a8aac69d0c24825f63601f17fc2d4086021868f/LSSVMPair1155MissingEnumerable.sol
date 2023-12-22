// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC1155} from "./IERC1155.sol";
import {Arrays} from "./Arrays.sol";
import {LSSVMPair1155} from "./LSSVMPair1155.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
/**
    @title An NFT/Token pair for an NFT that does not implement ERC721Enumerable
    @author boredGenius and 0xmons
 */
abstract contract LSSVMPair1155MissingEnumerable is LSSVMPair1155 { 
    using Arrays for uint256[];

    /// @inheritdoc LSSVMPair1155
    function _sendSpecificNFTsToRecipient(
        IERC1155 _nft,
        address nftRecipient,
        uint256 nftId,
        uint256 nftCount
    ) internal override {
        // Send NFTs to caller
        _nft.safeTransferFrom(
            address(this),
            nftRecipient,
            nftId,
            nftCount,
            ""
        );
    }

    /// @inheritdoc LSSVMPair1155
    function getAllHeldIds() external view override returns (uint256[] memory) {
        uint256[] memory Ids = new uint256[](1);
        Ids[0] = nftId;
        return Ids;
    }

    /**
        @dev When safeTransfering an ERC1155 in, we add ID to the idSet
        if it's the same collection used by pool. (As it doesn't auto-track because no ERC721Enumerable)
     */
    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory nftIds,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /// @inheritdoc LSSVMPair1155
    function withdrawERC1155(
        IERC1155 a,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external override onlyOwner {
        for (uint256 i; i < ids.length; ) {
            a.safeTransferFrom(address(this), msg.sender, ids[i], amounts[i], "");

            unchecked {
                ++i;
            }
        }
        
        emit NFTWithdrawal();
    }
}

