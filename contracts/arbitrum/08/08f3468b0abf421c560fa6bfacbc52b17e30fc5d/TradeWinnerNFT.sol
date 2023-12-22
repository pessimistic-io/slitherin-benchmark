// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC721AUpgradeable.sol";
import "./Strings.sol";
import { ITradeWinnerNFT } from "./ITradeWinnerNFT.sol";

import { MMNFTMetadata } from "./Structs.sol";
import {     IDCSVaultEntry } from "./IDCSVaultEntry.sol";
import { ITradeWinnerNFT } from "./ITradeWinnerNFT.sol";

contract TradeWinnerNFT is ITradeWinnerNFT, ERC721AUpgradeable {
    using Strings for uint256;

    address public immutable cegaEntry;

    mapping(uint256 => MMNFTMetadata) public tokensMetadata;

    modifier onlyCegaEntry() {
        require(msg.sender == cegaEntry, "Not CegaEntry");
        _;
    }

    constructor(address _cegaEntry) {
        cegaEntry = _cegaEntry;
    }

    function initialize() external initializerERC721A {
        __ERC721A_init("Cega MM NFT", "CMMNFT");
    }

    function mint(
        address to,
        MMNFTMetadata calldata _tokenMetadata
    ) external onlyCegaEntry returns (uint256) {
        uint256 nextTokenId = _nextTokenId();
        tokensMetadata[nextTokenId] = _tokenMetadata;

        _mint(to, 1);

        return nextTokenId;
    }

    function mintBatch(
        address to,
        MMNFTMetadata[] calldata _tokensMetadata
    ) external onlyCegaEntry returns (uint256[] memory) {
        uint256 firstTokenId = _nextTokenId();
        uint256 tokenCount = _tokensMetadata.length;

        uint256[] memory tokenIds = new uint256[](tokenCount);

        for (uint256 index = 0; index < tokenCount; index++) {
            uint256 nextToken = firstTokenId + index;
            tokenIds[index] = nextToken;
            tokensMetadata[nextToken] = _tokensMetadata[index];
        }

        _mint(to, tokenCount);

        return tokenIds;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        MMNFTMetadata memory metadata = tokensMetadata[tokenId];
        uint256 productId = IDCSVaultEntry(cegaEntry).getVaultProductId(
            metadata.vaultAddress
        );

        string memory json = string.concat(
            "{",
            '"name": "Token #',
            tokenId.toString(),
            '",',
            '"description": "A token with dynamic metadata",',
            '"attributes": [',
            '{ "trait_type": "VaultAddress", "value": "',
            Strings.toHexString(uint160(metadata.vaultAddress), 20),
            '" },',
            '{ "trait_type": "productId", "value": "',
            productId.toString(),
            '" },',
            '{ "trait_type": "Trade Start Date", "value": "',
            uint256(metadata.tradeStartDate).toString(),
            '" },',
            '{ "trait_type": "Trade End Date", "value": "',
            uint256(metadata.tradeEndDate).toString(),
            '" }',
            "],",
            "\"image\": \"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'><rect width='100%' height='100%' fill='blue' /></svg>\"",
            "}"
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }
}

