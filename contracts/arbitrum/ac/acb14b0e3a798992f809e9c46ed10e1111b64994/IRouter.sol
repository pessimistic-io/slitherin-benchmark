// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.7;

interface IRouter {
    function weth() external returns (address);

    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver,
        bytes calldata signedQuoteData
    ) external;

    function swapTokensToETH(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address payable _receiver,
        bytes calldata signedQuoteData
    ) external;

    function swapETHToTokens(
        address[] memory _path,
        uint256 _minOut,
        address _receiver,
        bytes calldata signedQuoteData
    ) external payable;
}

