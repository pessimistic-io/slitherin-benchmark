// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./OracleSimple.sol";
import "./SwapManagerBase.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract SwapManagerPolygon is SwapManagerBase {
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    /* solhint-enable */
    constructor() {
        addDex(
            "QUICKSWAP",
            0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff,
            0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32
        );
        addDex(
            "SUSHISWAP",
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506,
            0xc35DADB65012eC5796536bD9864eD8773aBc74C4
        );
    }

    function bestPathFixedInput(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _i
    ) public view override returns (address[] memory pathA, uint256 amountOut) {
        pathA = new address[](2);
        pathA[0] = _from;
        pathA[1] = _to;

        address[] memory pathB = new address[](3);
        pathB[0] = _from;
        pathB[1] = WMATIC;
        pathB[2] = _to;

        address[] memory pathC = new address[](3);
        pathC[0] = _from;
        pathC[1] = WETH;
        pathC[2] = _to;

        if (IUniswapV2Factory(factories[_i]).getPair(_from, _to) == address(0x0)) {
            // direct pair does not exist so just compare with from-WMATIC-to, from-WETH-to
            (pathA, amountOut) = comparePathsFixedInput(pathB, pathC, _amountIn, _i);
        } else {
            // compare three path.
            (pathA, amountOut) = comparePathsFixedInput(pathA, pathB, _amountIn, _i);
            (pathA, amountOut) = comparePathsFixedInput(pathA, pathC, _amountIn, _i);
        }
    }

    function bestPathFixedOutput(
        address _from,
        address _to,
        uint256 _amountOut,
        uint256 _i
    ) public view override returns (address[] memory pathA, uint256 amountIn) {
        pathA = new address[](2);
        pathA[0] = _from;
        pathA[1] = _to;

        address[] memory pathB = new address[](3);
        pathB[0] = _from;
        pathB[1] = WMATIC;
        pathB[2] = _to;

        address[] memory pathC = new address[](3);
        pathC[0] = _from;
        pathC[1] = WETH;
        pathC[2] = _to;
        // is one of these WMATIC
        if (IUniswapV2Factory(factories[_i]).getPair(_from, _to) == address(0x0)) {
            // direct pair do not exist. compare path B, C
            (pathA, amountIn) = comparePathsFixedOutput(pathB, pathC, _amountOut, _i);
        } else {
            // compare path B, C
            (pathA, amountIn) = comparePathsFixedOutput(pathA, pathB, _amountOut, _i);
            (pathA, amountIn) = comparePathsFixedOutput(pathA, pathC, _amountOut, _i);
        }
    }
}

