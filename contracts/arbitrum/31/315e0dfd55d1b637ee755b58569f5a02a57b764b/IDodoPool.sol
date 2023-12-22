// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IDodoPool {
    function _BASE_TOKEN_() external view returns (address);

    function _QUOTE_TOKEN_() external view returns (address);

    function sellBase(address to) external returns (uint256 receiveQuoteAmount);

    function sellQuote(address to) external returns (uint256 receiveBaseAmount);
}

