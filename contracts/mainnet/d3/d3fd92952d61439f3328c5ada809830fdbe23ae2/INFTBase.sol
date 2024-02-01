// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./ERC1155Upgradeable.sol";
import "./IAccessControlUpgradeable.sol";

// interface for INFTBase
interface INFTBase is IERC1155Upgradeable, IAccessControlUpgradeable {
    function burn(uint256 id, uint256 amount) external;
    
    function mint(address maker, uint256 id, uint256 amount) external returns(uint256);
    function mintBatch(address maker, uint256[] memory ids, uint256[] memory amounts) external returns(uint256[] memory);
}

