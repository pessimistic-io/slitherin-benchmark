// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

interface ISwapFishZap {
    function zap(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address[] memory _lpTokens, //[tokenA, tokenB]
        address[] calldata _path0,
        address[] calldata _path1,
        uint256[] memory _minAmountsSwap, //[A, B]
        uint256[] memory _minAmountsLP, //[amountAMin, amountBMin]
        address _to,
        uint256 _deadline
    ) external;

    function zapNative(
        address[] memory _lpTokens, //[tokenA, tokenB]
        address[] calldata _path0,
        address[] calldata _path1,
        uint256[] memory _minAmountsSwap, //[A, B]
        uint256[] memory _minAmountsLP, //[amountAMin, amountBMin]
        address _to,
        uint256 _deadline
    ) external payable;

    function getMinAmounts(
        uint256 _inputAmount,
        address[] calldata _path0,
        address[] calldata _path1
    )
        external
        view
        returns (
            uint256[2] memory _minAmountsSwap,
            uint256[2] memory _minAmountsLP
        );
}

