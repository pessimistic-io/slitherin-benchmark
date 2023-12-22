// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OwnableInternal.sol";
import "./ERC1155MetadataStorage.sol";

contract CardsUpdateMetadata is OwnableInternal {
    function setBaseURI(string memory baseURI) external onlyOwner {
        ERC1155MetadataStorage.layout().baseURI = baseURI;
    }
}

