// SPDX-License-Identifier: GPL-3.0-or-later

//solhint-disable-next-line compiler-version
pragma solidity >=0.5.0;

interface IArkenPairLongTermFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

