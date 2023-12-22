// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "./IERC721.sol";
import {Ownable} from "./Ownable.sol";

import {ITransferManagerNFT} from "./ITransferManagerNFT.sol";

/**
 * @title TransferManagerERC721
 * @notice It allows the transfer of ERC721 tokens.
 */
contract TransferManagerERC721 is ITransferManagerNFT, Ownable {
    address private CRYPTO_AVATARS_EXCHANGE;

    /**
     * @notice Constructor
     * @param _cryptoAvatarsExchange address of the CryptoAvatars exchange
     */
    constructor(address _cryptoAvatarsExchange) {
        CRYPTO_AVATARS_EXCHANGE = _cryptoAvatarsExchange;
    }

    function setExchange(address _cryptoAvatarsExchange) external onlyOwner {
        CRYPTO_AVATARS_EXCHANGE = _cryptoAvatarsExchange;
    }

    /**
     * @notice Transfer ERC721 token
     * @param collection address of the collection
     * @param from address of the sender
     * @param to address of the recipient
     * @param tokenId tokenId
     * @dev For ERC721, amount is not used
     */
    function transferNonFungibleToken(
        address collection,
        address from,
        address to,
        uint256 tokenId,
        uint256 /* amount */
    ) external override {
        require(
            msg.sender == CRYPTO_AVATARS_EXCHANGE,
            "Transfer: Only CryptoAvatars Exchange"
        );
        // https://docs.openzeppelin.com/contracts/2.x/api/token/erc721#IERC721-safeTransferFrom
        IERC721(collection).safeTransferFrom(from, to, tokenId);
    }
}

