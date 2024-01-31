//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./IERC721Enumerable.sol";

interface ICombatDragons is IERC721Enumerable {
    function mint(address) external;
}

