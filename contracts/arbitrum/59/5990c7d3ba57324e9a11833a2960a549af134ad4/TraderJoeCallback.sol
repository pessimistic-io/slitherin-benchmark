// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./IUniswapV2Pair.sol";
import "./OracleLibraryV2.sol";

contract TraderJoeCallback {
    /// @notice TraderJoe swap callback
    /// @param amount0 - The change in token0 reserves from the swap.
    /// @param amount1 - The change in token1 reserves from the swap.
    /// @param data - The data packed into the swap.
    function joeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address _tokenIn, uint24 _swapFee) = abi.decode(data, (bool, address, uint24));

        uint256 amountOut = _zeroForOne ? amount1 : amount0;
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(msg.sender).getReserves();

        uint256 amountIn = OracleLibraryV2.getAmountIn(
            amountOut, _zeroForOne ? reserve0 : reserve1, _zeroForOne ? reserve1 : reserve0, _swapFee
        );
        IERC20(_tokenIn).transfer(msg.sender, amountIn);
    }
}

