// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ISolidStateERC721} from "./ISolidStateERC721.sol";

interface IBinaryVaultNFTFacet is ISolidStateERC721 {
    function nextTokenId() external view returns (uint256);

    function mint(address owner) external;

    function exists(uint256 tokenId) external view returns (bool);

    function burn(uint256 tokenId) external;

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory);
}

