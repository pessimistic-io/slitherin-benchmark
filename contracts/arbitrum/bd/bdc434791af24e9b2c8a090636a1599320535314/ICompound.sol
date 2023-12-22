// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IComptrollerCompound {
    function enterMarkets(address[] calldata xTokens)
        external
        returns (uint256[] memory);

    function getAllMarkets() external view returns (address[] memory);

    function getAssetsIn(address account)
        external
        view
        returns (address[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256 err,
            uint256 liquidity,
            uint256 shortfall
        );

    function checkMembership(address account, address cToken)
        external
        view
        returns (bool);
}

interface IInterestRateModel {
    function blocksPerYear() external view returns (uint256);
}

