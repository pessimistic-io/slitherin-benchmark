// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC721.sol";
import "./IAccessControl.sol";

interface IPlanckCat is IERC721, IAccessControl {
    function safeMint(address to) external;

    function safeMintCustom(address to, string memory _customURI) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

