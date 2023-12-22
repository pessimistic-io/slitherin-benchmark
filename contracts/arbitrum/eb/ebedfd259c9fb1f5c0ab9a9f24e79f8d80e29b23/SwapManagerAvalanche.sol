// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./OracleSimple.sol";
import "./SwapManagerBase.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract SwapManagerAvalanche is SwapManagerBase {
    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant WETH = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;

    /* solhint-enable */
    constructor() {
        addDex(
            "TRADERJOE",
            0x60aE616a2155Ee3d9A68541Ba4544862310933d4,
            0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10
        );
        addDex(
            "PANGOLIN",
            0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106,
            0xefa94DE7a4656D787667C749f7E1223D71E9FD88
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
        pathB[1] = WAVAX;
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
        pathB[1] = WAVAX;
        pathB[2] = _to;

        address[] memory pathC = new address[](3);
        pathC[0] = _from;
        pathC[1] = WETH;
        pathC[2] = _to;
        // is one of these WAVAX
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

