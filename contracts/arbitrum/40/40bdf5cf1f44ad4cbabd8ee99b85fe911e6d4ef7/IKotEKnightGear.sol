// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface IKotEKnightGear is IERC1155Upgradeable {
    function mint(address wallet, uint256 id, uint256 amount) external;
    function burn(address wallet, uint256 id, uint256 amount) external;
}
