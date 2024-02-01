// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC1155Base, ERC1155BaseInternal} from "./ERC1155Base.sol";
import {ERC1155Enumerable} from "./ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "./ERC1155EnumerableInternal.sol";
import {IKomonERC1155} from "./IKomonERC1155.sol";
import {ERC165} from "./ERC165.sol";
import {KomonAccessControlBaseStorage} from "./KomonAccessControlBaseStorage.sol";

/**
 * @title Komon ERC1155 implementation
 */
abstract contract KomonERC1155 is
    IKomonERC1155,
    ERC1155Base,
    ERC1155Enumerable,
    ERC165
{
    /**
     * @inheritdoc ERC1155BaseInternal
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
        override(ERC1155BaseInternal, ERC1155EnumerableInternal)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _createSpaceToken(
        uint256[] calldata maxSupplies,
        uint256[] calldata prices,
        uint8[] calldata percentages,
        address creatorAccount
    ) internal {
        uint256 length = maxSupplies.length;
        require(
            length == prices.length && prices.length == percentages.length,
            "MaxSupplies, prices and percentage length mismatch"
        );
        uint256[] memory tokenIds = new uint256[](length);
        uint256[] memory pricesArray = new uint256[](length);
        uint8[] memory percentageArray = new uint8[](length);

        for (uint256 i = 0; i < length; ) {
            uint256 newTokenId = getNewTokenId();
            setTokenMaxSupply(newTokenId, maxSupplies[i]);
            _setCreatorTokenOwner(newTokenId, creatorAccount);

            tokenIds[i] = newTokenId;
            pricesArray[i] = prices[i];
            percentageArray[i] = percentages[i];

            emit CreatedSpaceToken(
                newTokenId,
                maxSupplies[i],
                prices[i],
                percentages[i],
                creatorAccount
            );

            unchecked {
                ++i;
            }
        }

        setTokensPrice(tokenIds, pricesArray, false);
        setTokensPercentage(tokenIds, percentageArray, false);
    }

    function _setCreatorTokenOwner(uint256 newTokenId, address creatorAccount)
        private
    {
        setCreatorTokenOwner(newTokenId, creatorAccount);
        KomonAccessControlBaseStorage.grantCreatorRole(creatorAccount);
    }

    function _mintInternalKey(uint256 amount) internal {
        uint256 newTokenId = getNewTokenId();
        _mint(msg.sender, newTokenId, amount, "");
        emit InternalKomonKeysMinted(msg.sender, newTokenId, amount);
    }
}

