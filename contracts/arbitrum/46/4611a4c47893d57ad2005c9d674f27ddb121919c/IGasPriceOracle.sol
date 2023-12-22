// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

interface IGasPriceOracle {
    function relativeGasPrice(
        uint32 dstChainSlug
    ) external view returns (uint256);

    function sourceGasPrice() external view returns (uint256);
}

