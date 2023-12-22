// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVNFT.sol";
import "./IERC721Upgradeable.sol";

interface ISurfVoucher is IERC721Upgradeable, IVNFT {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);
    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    function slotAdminOf(uint256 slot) external view returns (address);

    function mint(uint256 slot, address user, uint256 units) external returns (uint256);

    function burn(uint256 tokenId) external;
}
