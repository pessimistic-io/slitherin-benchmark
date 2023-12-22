//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IDodoApporveProxy {
    function _DODO_APPROVE_() external view returns (address);
}

interface IDodoV2Proxy02 {
    function _DVM_FACTORY_() external view returns (address);

    function _DODO_APPROVE_PROXY_() external view returns (address);

    function dodoSwapV2TokenToToken(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory dodoPairs,
        uint256 directions,
        bool isIncentive,
        uint256 deadLine
    ) external returns (uint256 returnAmount);
}

interface IDodoFactory {
    function getDODOPoolBidirection(address token0, address token1) external view returns (address[] memory, address[] memory);
}

interface IDodoPool {
    function querySellBase(address trader, uint256 payBaseAmount) external view returns (uint256 receiveQuoteAmount, uint256 mtFee);

    function querySellQuote(address trader, uint256 payQuoteAmount) external view returns (uint256 receiveQuoteAmount, uint256 mtFee);

    function _BASE_TOKEN_() external view returns (address);

    function _QUOTE_TOKEN_() external view returns (address);
}

