// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

interface IPairFactory {
    function pairByTokens(
        address _tokenA,
        address _tokenB
    ) external view returns (address);
}

