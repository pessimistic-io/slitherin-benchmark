// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IDodoSingleAssetPool {
    function withdrawBase(uint256 amount) external returns (uint256);

    function depositBase(uint256 amount) external returns (uint256);

    function withdrawQuote(uint256 amount) external returns (uint256);

    function depositQuote(uint256 amount) external returns (uint256);

    function withdrawAllBase() external returns (uint256);

    function withdrawAllQuote() external returns (uint256);

    function _BASE_TOKEN_() external returns (address);

    function _QUOTE_TOKEN_() external returns (address);

    function _BASE_CAPITAL_TOKEN_() external returns (address);

    function _QUOTE_CAPITAL_TOKEN_() external returns (address);

    function getExpectedTarget()
        external
        view
        returns (uint256 baseTarget, uint256 quoteTarget);

    function getWithdrawBasePenalty(uint256 amount)
        external
        view
        returns (uint256);

    function getWithdrawQuotePenalty(uint256 amount)
        external
        view
        returns (uint256);
}

