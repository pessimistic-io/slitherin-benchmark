// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC721A.sol";

interface IMA is IERC721A {
    // blue 1/ green 0
    function characters(
        uint256
    ) external view returns (uint256 quality, uint256 level, uint256 score);

    function tokensOfOwner(address) external view returns (uint256[] memory);
}

