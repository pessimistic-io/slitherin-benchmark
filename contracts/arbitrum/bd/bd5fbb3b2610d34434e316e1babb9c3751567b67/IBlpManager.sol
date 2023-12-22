// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

interface IBlpManager {
    function provideForAccount(
        uint256 tokenXAmount,
        uint256 minMint,
        address account
    ) external returns (uint256 mint);

    function withdrawForAccount(uint256 tokenXAmount, address account)
        external
        returns (uint256 burn);

    function toTokenX(uint256 amount) external view returns (uint256);
}

