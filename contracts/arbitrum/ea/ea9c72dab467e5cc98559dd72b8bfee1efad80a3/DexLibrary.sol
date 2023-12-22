// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IFactory.sol";
import "./IPair.sol";


library DexLibrary {

    error DexLibraryIdenticalAddress();
    error DexLibraryInvalidAddress(address account);

    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IPair(IFactory(factory).getPair(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert DexLibraryIdenticalAddress();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert DexLibraryInvalidAddress(address(0));
    }
}

