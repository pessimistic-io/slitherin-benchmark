//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IGMXVault {
    function whitelistedTokens(address) external view returns (bool);

    function stableTokens(address) external view returns (bool);

    function shortableTokens(address) external view returns (bool);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        );
}

