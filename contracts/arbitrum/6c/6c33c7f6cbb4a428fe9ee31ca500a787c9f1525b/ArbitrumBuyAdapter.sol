// SPDX-License-Identifier: ISC

pragma solidity 0.7.5;

import "./NewUniswapV2.sol";
import "./UniswapV3.sol";
import "./AugustusRFQ.sol";
import "./BalancerV2.sol";
import "./HashFlow.sol";
import "./TraderJoeV2.sol";
import "./TraderJoeV21.sol";
import "./IBuyAdapter.sol";

/**
 * @dev This contract will route call to:
 * 1 - UniswapV2Forks
 * 2 - UniswapV3
 * 3 - AugustusRFQ
 * 4 - HashFlow
 * 5 - TraderJoeV2
 * 6 - BalancerV2
 * 7 - TraderJoeV21
 * The above are the indexes
 */

contract ArbitrumBuyAdapter is
    IBuyAdapter,
    NewUniswapV2,
    UniswapV3,
    AugustusRFQ,
    HashFlow,
    TraderJoeV2,
    TraderJoeV21,
    BalancerV2
{
    using SafeMath for uint256;

    constructor(address _weth) public WethProvider(_weth) {}

    function initialize(bytes calldata data) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function buy(
        uint256 index,
        IERC20 fromToken,
        IERC20 toToken,
        uint256 maxFromAmount,
        uint256 toAmount,
        address targetExchange,
        bytes calldata payload
    ) external payable override {
        if (index == 1) {
            buyOnUniswapFork(fromToken, toToken, maxFromAmount, toAmount, payload);
        } else if (index == 2) {
            buyOnUniswapV3(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else if (index == 3) {
            buyOnAugustusRFQ(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else if (index == 4) {
            buyOnHashFlow(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else if (index == 5) {
            buyOnTraderJoeV2(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else if (index == 6) {
            buyOnBalancerV2(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else if (index == 7) {
            buyOnTraderJoeV21(fromToken, toToken, maxFromAmount, toAmount, targetExchange, payload);
        } else {
            revert("Index not supported");
        }
    }
}

