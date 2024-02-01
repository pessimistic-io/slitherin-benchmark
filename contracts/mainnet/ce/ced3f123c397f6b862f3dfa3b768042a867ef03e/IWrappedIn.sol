// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

interface IWrappedIn {
    function stake(
        uint256 tokenId,
        uint256 amount,
        address to
    ) external;

    function redeem(
        uint256 tokenId,
        uint256 amount,
        address to
    ) external;

    function initializeWrap(
        address originalAddress_
    ) external;
}

