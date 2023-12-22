// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./OracleSimple.sol";
import "./SwapManagerBase.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract SwapManagerArbitrum is SwapManagerBase {
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /**
     * @dev The Arbitrum has only Sushiswap as UniswapV2 fork DEX
     */
    constructor() {
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
    ) public view override returns (address[] memory path, uint256 amountOut) {
        path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        if (_from == WETH || _to == WETH) {
            amountOut = safeGetAmountsOut(_amountIn, path, _i)[path.length - 1];
            return (path, amountOut);
        }

        address[] memory pathB = new address[](3);
        pathB[0] = _from;
        pathB[1] = WETH;
        pathB[2] = _to;
        // is one of these WETH
        if (IUniswapV2Factory(factories[_i]).getPair(_from, _to) == address(0x0)) {
            // does a direct liquidity pair not exist?
            amountOut = safeGetAmountsOut(_amountIn, pathB, _i)[pathB.length - 1];
            path = pathB;
        } else {
            // if a direct pair exists, we want to know whether pathA or path B is better
            (path, amountOut) = comparePathsFixedInput(path, pathB, _amountIn, _i);
        }
    }

    function bestPathFixedOutput(
        address _from,
        address _to,
        uint256 _amountOut,
        uint256 _i
    ) public view override returns (address[] memory path, uint256 amountIn) {
        path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        if (_from == WETH || _to == WETH) {
            amountIn = safeGetAmountsIn(_amountOut, path, _i)[0];
            return (path, amountIn);
        }

        address[] memory pathB = new address[](3);
        pathB[0] = _from;
        pathB[1] = WETH;
        pathB[2] = _to;

        // is one of these WETH
        if (IUniswapV2Factory(factories[_i]).getPair(_from, _to) == address(0x0)) {
            // does a direct liquidity pair not exist?
            amountIn = safeGetAmountsIn(_amountOut, pathB, _i)[0];
            path = pathB;
        } else {
            // if a direct pair exists, we want to know whether pathA or path B is better
            (path, amountIn) = comparePathsFixedOutput(path, pathB, _amountOut, _i);
        }
    }
}

