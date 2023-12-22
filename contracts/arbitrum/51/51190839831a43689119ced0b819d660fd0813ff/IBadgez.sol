// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface IBadgez is IERC1155Upgradeable {

    function mintIfNeeded(address _to, uint256 _id) external;
}
