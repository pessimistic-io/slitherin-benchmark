//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC1155Upgradeable.sol";

interface IItem is IERC1155Upgradeable {
  function mintItems(uint256 itemId, address receiver, uint256 amount, bytes memory data) external;
}

