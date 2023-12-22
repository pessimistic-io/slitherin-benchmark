// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./I1inchAggregationRouterV4.sol";
import "./ITokenSwapper.sol";
import "./Errors.sol";

contract OneInchV4Swapper is ITokenSwapper {
    using SafeERC20 for IERC20;

    struct SwapParams {
        address caller;
        I1inchAggregationRouterV4.SwapDescription desc;
        bytes data;
    }

    I1inchAggregationRouterV4 public router;

    constructor(address _router) {
        router = I1inchAggregationRouterV4(payable(_router));
    }

    /*
    * @notice Swaps `amountIn` of `tokenIn` for `amountOut` of `tokenOut`, with a minimum output amount of `minAmountOut`.
    * @param tokenIn The address of the token to be swapped. Must match the `srcToken` parameter in `externalData`.
    * @param amountIn The amount of `tokenIn` to be swapped. Must match the `amount` parameter in `externalData`.
    * @param tokenOut The address of the desired output token. Must match the `dstToken` parameter in `externalData`.
    * @param minAmountOut The minimum amount of `tokenOut` that must be received in the swap. Must match the `minReturnAmount` parameter in `externalData`.
    * @param externalData A bytes value containing the encoded swap parameters.
    * @return The actual amount of `tokenOut` received in the swap.
    */
    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut, bytes memory externalData)
        external
        returns (uint256 amountOut)
    {
        SwapParams memory _swap = abi.decode(externalData, (SwapParams));

        if (tokenIn != _swap.desc.srcToken) {
            revert Errors.InvalidTokenIn(tokenIn, _swap.desc.srcToken);
        }
        if (tokenOut != _swap.desc.dstToken) {
            revert Errors.InvalidTokenOut(tokenOut, _swap.desc.dstToken);
        }
        if (amountIn != _swap.desc.amount) {
            revert Errors.InvalidAmountIn(amountIn, _swap.desc.amount);
        }
        if (msg.sender != _swap.desc.dstReceiver) {
            revert Errors.InvalidReceiver(msg.sender, _swap.desc.dstReceiver);
        }
        if (minAmountOut > _swap.desc.minReturnAmount) {
            revert Errors.InvalidMinAmountOut(minAmountOut, _swap.desc.minReturnAmount);
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), _swap.desc.amount);
        IERC20(tokenIn).safeApprove(address(router), _swap.desc.amount);
        (uint256 returnAmount,) = router.swap(_swap.caller, _swap.desc, _swap.data);
        IERC20(tokenIn).safeApprove(address(router), 0);

        return returnAmount;
    }
}

