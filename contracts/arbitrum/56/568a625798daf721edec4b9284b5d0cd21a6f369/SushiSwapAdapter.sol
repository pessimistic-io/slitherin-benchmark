// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {OperableKeepable} from "./OperableKeepable.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {IUniswapV2Router} from "./IUniswapV2Router.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ISwap} from "./ISwap.sol";
import {AssetsPricing} from "./AssetsPricing.sol";
import {ILpsRegistry} from "./LpsRegistry.sol";

contract SushiSwapAdapter is ISwap, OperableKeepable {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // Sushi Swap Router
    IUniswapV2Router private constant SUSHI_ROUTER = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    // @notice Internal representation of 100%
    uint256 private constant BASIS_POINTS = 1e12;

    // @notice Slippage to avoid reverts after simulations
    uint256 private slippage;

    // @notice Wrapped Ether
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Store the LP pair address for a given token0
    // tokenIn => tokenOut => LP
    // Use public function to get the LP address for the given route.
    mapping(address => mapping(address => address)) private lpAddress;

    ILpsRegistry private lpsRegistry;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initializeSwap(address _lpsRegistry) external initializer {
        slippage = (98 * 1e12) / 100;

        lpsRegistry = ILpsRegistry(_lpsRegistry);

        __Governable_init(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY OPERATOR                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Perform Swap.
     * @param _data Data needed for the swap.
     * @return Amount out
     */
    function swap(SwapData memory _data) external onlyOperatorOrKeeper returns (uint256) {
        return _swap(_data);
    }

    /**
     * @notice Perform Swap of any token to weth.
     * @param _token Asset to swap.
     * @param _amount Amount to swap.
     */
    function swapTokensToEth(address _token, uint256 _amount) external onlyOperatorOrKeeper {
        IUniswapV2Router router = SUSHI_ROUTER;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_token).safeApprove(address(router), _amount);

        address[] memory path = new address[](2);

        path[0] = _token;
        path[1] = WETH;

        address pair = lpsRegistry.getLpAddress(_token, WETH);

        // This takes in consideration slippage + fees
        uint256 min = AssetsPricing.getAmountOut(pair, _amount, _token, WETH);

        // Apply slippage to avoid an unlikely revert
        min = _applySlippage(min, slippage);

        uint256[] memory amounts = router.swapExactTokensForTokens(_amount, min, path, msg.sender, block.timestamp);

        emit AdapterSwap(address(this), _token, WETH, msg.sender, _amount, amounts[amounts.length - 1]);
    }

    /**
     * @notice Perform more than one swap
     * @param _data Data needed to do many swaps.
     * @return _amount Amounts out.
     */
    function batchSwap(SwapData[] memory _data) external returns (uint256[] memory) {
        uint256 length = _data.length;

        uint256[] memory outputs = new uint256[](length);

        for (uint256 i; i < length;) {
            outputs[i] = _swap(_data[i]);

            unchecked {
                ++i;
            }
        }

        return outputs;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Default slippage for safety measures
     * @param _slippage Default slippage
     */
    function setSlippage(uint256 _slippage) external onlyGovernor {
        if (_slippage == 0 || _slippage > BASIS_POINTS) revert InvalidSlippage();

        slippage = _slippage;
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyGovernor {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    PRIVATE                                 */
    /* -------------------------------------------------------------------------- */

    function _swap(SwapData memory _data) private returns (uint256) {
        // Send tokens from msg.sender to here
        IERC20(_data.tokenIn).safeTransferFrom(msg.sender, address(this), _data.amountIn);

        address pair = lpsRegistry.getLpAddress(_data.tokenIn, _data.tokenOut);

        uint256 minAmountOut;

        address[] memory path;

        // In case the swap is not to WETH, we are first converting it to WETH and then to the token out since WETH pair are more liquid.
        path = new address[](2);

        path[0] = _data.tokenIn;
        path[1] = _data.tokenOut;

        // Gets amount out in a single hop swap
        minAmountOut = AssetsPricing.getAmountOut(pair, _data.amountIn, _data.tokenIn, _data.tokenOut);

        // Apply slippage to avoid unlikely revert
        minAmountOut = _applySlippage(minAmountOut, slippage);

        // Approve Sushi router to spend received tokens
        IERC20(_data.tokenIn).safeApprove(address(SUSHI_ROUTER), _data.amountIn);

        if (minAmountOut > 0) {
            uint256[] memory amounts =
                SUSHI_ROUTER.swapExactTokensForTokens(_data.amountIn, minAmountOut, path, msg.sender, block.timestamp);

            emit AdapterSwap(
                address(this), _data.tokenIn, _data.tokenOut, msg.sender, _data.amountIn, amounts[amounts.length - 1]
            );

            return amounts[amounts.length - 1];
        } else {
            return 0;
        }
    }

    function _applySlippage(uint256 _amountOut, uint256 _slippage) private pure returns (uint256) {
        return _amountOut.mulDivDown(_slippage, BASIS_POINTS);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error InvalidSlippage();
    error ZeroAddress();
    error ZeroAmount(address _token);
    error FailSendETH();
}

