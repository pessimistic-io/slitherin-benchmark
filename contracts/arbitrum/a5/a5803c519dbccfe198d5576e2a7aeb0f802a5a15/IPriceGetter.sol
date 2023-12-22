// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

interface IPriceGetter {
    function getLatestPrice(string memory _tokenName)
        external
        returns (uint256 price);

    function getLatestPrice(address _token) external returns (uint256 price);
}

