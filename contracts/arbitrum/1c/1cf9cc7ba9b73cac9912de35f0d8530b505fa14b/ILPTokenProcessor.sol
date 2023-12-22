// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ILPTokenProcessor {
    function addTokenForSwapping(
        address tokenAddress,
        address routerFactory,
        bool isV2,
        address referrer,
        uint256 referrerShare
    ) external;

    function getRouter(address lpTokenAddress) external view returns (address);

    function getV3Position(address tokenAddress, uint256 tokenId)
        external
        view
        returns (
            address,
            address,
            uint128
        );

    function isV2LiquidityPoolToken(address tokenAddress) external view returns (bool);

    function isV3LiquidityPoolToken(address tokenAddress, uint256 tokenId) external view returns (bool);

    function swapTokens(
        address sourceToken,
        uint256 sourceAmount,
        address destinationToken,
        address receiver,
        address routerAddress
    ) external returns (bool);
}

