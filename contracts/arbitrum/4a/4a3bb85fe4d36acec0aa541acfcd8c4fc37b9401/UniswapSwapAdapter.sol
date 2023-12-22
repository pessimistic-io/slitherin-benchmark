// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "./IERC20.sol";
import { ISwapRouter02 } from "./ISwapRouter02.sol";

import { Controllable } from "./Controllable.sol";

error incorrectOutputToken();

/**
 * @dev this contract exposes necessary logic to swap between tokens using Uniswap.
 * note that it should only hold tokens mid-transaction. Any tokens transferred in outside of a swap can be stolen.
 */
contract UniswapSwapAdapter is Controllable {
    address public immutable swapRouter;

    constructor(address _controller, address _swapRouter) Controllable(_controller) {
        swapRouter = _swapRouter;
    }

    // exactInput
    function swap(address _outputToken, bytes calldata _swapData) external onlyVault returns (uint256) {
        // Decode swap data
        (uint256 deadline, uint256 _amountIn, uint256 _amountOutMinimum, bytes memory _path) = abi.decode(
            _swapData,
            (uint256, uint256, uint256, bytes)
        );

        /*
            Anatomy of swap data:
            32 bytes for deadline
            32 bytes for _amountIn
            32 bytes for _amountOutMinimum
            Then the _path bytes:
                32 bytes for path offset
                32 bytes for path length
                20 bytes for 1st address
                3 bytes for 1st fee
                20 bytes for 2nd address
                Then continue adding 23 bytes for each additional pool until the end of the path.
            Finally, pad the end with 0 bytes until the total _swapData length is a multiple of 32.

            Total length of _swapData = 96 + 64 + path data length + padding
            Therefore the last address in the path will appear at index 160 + path data length - 20 = 140 + _path.length

            Here, check that that last address matches the contract-specified output token.
        */
        uint256 lastAddressStart = 140 + _path.length;
        address swapOutputToken = address(bytes20(_swapData[lastAddressStart:lastAddressStart + 20]));

        if (swapOutputToken != _outputToken) {
            // The keeper-inputted Output Token differs from what the contract says it must be.
            revert incorrectOutputToken();
        }

        // Perform swap (this will fail if tokens haven't been transferred in, or haven't been approved)
        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: _path,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum
        });

        return ISwapRouter02(swapRouter).exactInput(params);
    }

    /**
     * @dev approve any token to the swapRouter.
     * note this is calleable by anyone.
     */
    function approveTokens(address _tokenIn) external {
        IERC20(_tokenIn).approve(swapRouter, type(uint256).max);
    }
}

