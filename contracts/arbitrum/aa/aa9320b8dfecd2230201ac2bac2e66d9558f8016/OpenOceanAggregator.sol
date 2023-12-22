// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IOpenOceanExchange, IOpenOceanCaller } from "./IOpenOceanExchange.sol";
import { IERC20 } from "./IERC20.sol";

library OpenOceanAggregator {
    // =============================================================
    //                         Errors
    // =============================================================

    error WRONG_TOKEN_IN(); // 0xf6b8648c
    error WRONG_TOKEN_OUT(); // 0x5e8f1f5b
    error WRONG_AMOUNT(); // 0xc6ea1a16
    error WRONG_DST(); // 0xcb0b65a6
    error SWAP_ERROR(); // 0xcbe60bba
    error SWAP_METHOD_NOT_IDENTIFIED(); // 0xc257a710

    // =============================================================
    //                        Constants
    // =============================================================

    address constant router = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;

    // =============================================================
    //                        Functions
    // =============================================================

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata data
    ) public returns (uint256 outAmount) {
        IERC20(tokenIn).approve(address(router), amount);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        bytes4 method = _getMethod(data);

        // swap
        if (
            method ==
            bytes4(
                keccak256(
                    'swap(address,(address,address,address,address,uint256,uint256,uint256,uint256,address,bytes),(uint256,uint256,uint256,bytes)[])'
                )
            )
        ) {
            (, IOpenOceanExchange.SwapDescription memory desc, ) = abi.decode(
                data[4:],
                (IOpenOceanCaller, IOpenOceanExchange.SwapDescription, IOpenOceanCaller.CallDescription[])
            );

            if (tokenIn != address(desc.srcToken)) revert WRONG_TOKEN_IN();
            if (tokenOut != address(desc.dstToken)) revert WRONG_TOKEN_OUT();
            if (amount != desc.amount) revert WRONG_AMOUNT();
            if (address(this) != desc.dstReceiver) revert WRONG_DST();

            _callOpenOcean(data);
        }
        // uniswapV3SwapTo
        else if (method == bytes4(keccak256('uniswapV3SwapTo(address,uint256,uint256,uint256[])'))) {
            (address recipient, uint256 swapAmount, , ) = abi.decode(data[4:], (address, uint256, uint256, uint256[]));
            if (address(this) != recipient) revert WRONG_DST();
            if (amount != swapAmount) revert WRONG_AMOUNT();

            _callOpenOcean(data);
        }
        // callUniswapTo
        else if (method == bytes4(keccak256('callUniswapTo(address,uint256,uint256,bytes32[],address)'))) {
            (address srcToken, uint256 swapAmount, , , address recipient) = abi.decode(
                data[4:],
                (address, uint256, uint256, bytes32[], address)
            );
            if (tokenIn != srcToken) revert WRONG_TOKEN_IN();
            if (amount != swapAmount) revert WRONG_AMOUNT();
            if (address(this) != recipient) revert WRONG_DST();

            _callOpenOcean(data);
        } else {
            revert SWAP_METHOD_NOT_IDENTIFIED();
        }

        return IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
    }

    function _getMethod(bytes memory data) internal pure returns (bytes4 method) {
        assembly {
            method := mload(add(data, add(32, 0)))
        }
    }

    function _callOpenOcean(bytes memory data) internal {
        (bool success, bytes memory result) = address(router).call(data);
        if (!success) {
            if (result.length < 68) revert SWAP_ERROR();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }
}

