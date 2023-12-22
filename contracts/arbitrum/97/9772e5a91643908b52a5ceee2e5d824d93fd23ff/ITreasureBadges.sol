// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface ITreasureBadges is IERC1155Upgradeable {
    function adminMint(address _to, uint256 _id) external;
    function adminBurn(address _to, uint256 _id, uint256 _amount) external;
}

