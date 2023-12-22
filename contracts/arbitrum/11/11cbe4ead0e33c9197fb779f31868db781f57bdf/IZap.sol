// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IZap {
    /// @dev get zap data
    function slippageToleranceNumerator() external view returns (uint24);

    function getSwapInfo(
        address inputToken,
        address outputToken
    )
        external
        view
        returns (
            bool isPathDefined,
            address[] memory swapPathArray,
            uint24[] memory swapTradeFeeArray
        );

    function getTokenExchangeRate(
        address inputToken,
        address outputToken
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint256 tokenPriceWith18Decimals
        );

    function getMinimumSwapOutAmount(
        address inputToken,
        address outputToken,
        uint256 inputAmount
    ) external view returns (uint256 minimumSwapOutAmount);

    /// @dev swapToken
    function swapToken(
        bool isETH,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        address recipient
    ) external payable returns (uint256 outputAmount);

    function swapTokenWithMinimumOutput(
        bool isETH,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minimumSwapOutAmount,
        address recipient
    ) external payable returns (uint256 outputAmount);
}

