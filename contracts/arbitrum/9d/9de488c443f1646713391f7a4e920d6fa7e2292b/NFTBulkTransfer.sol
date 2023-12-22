// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./IERC1155.sol";
import "./IERC721.sol";

contract NFTBulkTransfer {

    function safeERC721BulkTransferToMultipleWallets(
        IERC721 erc721Contract,
        address[] calldata tos,
        uint256[] calldata tokenIds
    ) external {
        uint256 length = tokenIds.length;
        require(tos.length == length, "invalid input");

        for (uint256 i = 0; i < length; ) {
            uint256 tokenId = tokenIds[i];
            address to = tos[i];

            require(msg.sender == erc721Contract.ownerOf(tokenId), "not owner");

            erc721Contract.safeTransferFrom(msg.sender, to, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    function safeERC1155BulkTransferToMultipleWallets(
        IERC1155 erc1155Contract,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external {
        uint256 length = tokenIds.length;
        require(tos.length == length, "invalid input");
        require(amounts.length == length, "invalid input");

        for (uint256 i = 0; i < length; ) {
            address to = tos[i];
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            
            require(erc1155Contract.balanceOf(msg.sender, tokenId) >= amount, "insufficient balance");

            erc1155Contract.safeTransferFrom(msg.sender, to, tokenId, amount, "");
            unchecked {
                ++i;
            }
        }
    }
}

