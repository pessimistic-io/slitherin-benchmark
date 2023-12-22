// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVNFT.sol";
import "./IERC721EnumerableUpgradeable.sol";
import "./IERC721MetadataUpgradeable.sol";

interface ISurfVoucher is IERC721Upgradeable, IERC721MetadataUpgradeable, IERC721EnumerableUpgradeable , IVNFT {
    function slotAdminOf(uint256 slot) external view returns (address);

    function mint(uint256 slot, address user, uint256 units) external returns (uint256);

    function burn(uint256 tokenId) external;
}
