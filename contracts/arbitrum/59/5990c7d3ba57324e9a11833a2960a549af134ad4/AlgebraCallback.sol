// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./IERC20.sol";

contract AlgebraCallback {
    ///@notice Algebra callback function called during a swap on a algebra liqudity pool.
    ///@param amount0 - The change in token0 reserves from the swap.
    ///@param amount1 - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function algebraSwapCallback(int256 amount0, int256 amount1, bytes calldata data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address _tokenIn, address _sender) = abi.decode(data, (bool, address, address));

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne ? uint256(amount0) : uint256(amount1);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(_tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(_tokenIn).transfer(msg.sender, amountIn);
        }
    }
}

