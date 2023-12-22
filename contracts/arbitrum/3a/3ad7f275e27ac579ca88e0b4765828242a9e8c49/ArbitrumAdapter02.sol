// SPDX-License-Identifier: ISC

pragma solidity 0.7.5;
pragma abicoder v2;

import "./IAdapter.sol";
import "./DystopiaUniswapV2Fork.sol";
import "./TraderJoeV2.sol";
import "./WooFiV2Adapter.sol";
import "./TraderJoeV21.sol";

/**
 * @dev This contract will route call to:
 * 1 - DystopiaUniswapV2Fork
 * 2 - TraderJoe2
 * 3 - WooFiV2
 * 4 - TraderJoeV2
 * The above are the indexes
 */
contract ArbitrumAdapter02 is IAdapter, DystopiaUniswapV2Fork, TraderJoeV2, WooFiV2Adapter, TraderJoeV21 {
    using SafeMath for uint256;

    /* solhint-disable no-empty-blocks */
    constructor(address _weth) public WethProvider(_weth) {}

    /* solhint-disable no-empty-blocks */
    function initialize(bytes calldata) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function swap(
        IERC20 fromToken,
        IERC20 toToken,
        uint256 fromAmount,
        uint256,
        Utils.Route[] calldata route
    ) external payable override {
        for (uint256 i = 0; i < route.length; i++) {
            if (route[i].index == 1) {
                swapOnDystopiaUniswapV2Fork(
                    fromToken,
                    toToken,
                    fromAmount.mul(route[i].percent).div(10000),
                    route[i].payload
                );
            } else if (route[i].index == 2) {
                // swap on Maverick
                swapOnTraderJoeV2(
                    fromToken,
                    toToken,
                    fromAmount.mul(route[i].percent).div(10000),
                    route[i].targetExchange,
                    route[i].payload
                );
            } else if (route[i].index == 3) {
                swapOnWooFiV2(
                    fromToken,
                    toToken,
                    fromAmount.mul(route[i].percent).div(10000),
                    route[i].targetExchange,
                    route[i].payload
                );
            } else if (route[i].index == 4) {
                swapOnTraderJoeV21(
                    fromToken,
                    toToken,
                    fromAmount.mul(route[i].percent).div(10000),
                    route[i].targetExchange,
                    route[i].payload
                );
            } else {
                revert("Index not supported");
            }
        }
    }
}

