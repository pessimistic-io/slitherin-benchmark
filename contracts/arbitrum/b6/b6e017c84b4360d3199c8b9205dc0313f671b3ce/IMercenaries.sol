// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Metadata.sol";

interface IMercenaries is IERC721Metadata {
        function mint(address to, bytes16[] calldata traits) external;
        function wrap(address account, uint256 wrappedTokenID, address collectionAddress) external;
        function updateTraits(uint256 tokenID, bytes16[] calldata traits) external;
}
