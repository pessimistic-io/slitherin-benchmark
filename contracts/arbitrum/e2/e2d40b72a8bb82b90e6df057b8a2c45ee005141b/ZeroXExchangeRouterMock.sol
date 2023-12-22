// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./I0xExchangeRouter.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { Constants } from "./Constants.sol";

contract ZeroXExchangeRouterMock is I0xExchangeRouter {
    using SafeERC20 for IERC20;

    uint public exchangeRateBips = Constants.BASIS_POINTS_DIVISOR;

    function setExchangeRateInBips(uint256 rate) external {
        exchangeRateBips = rate;
    }

    function transformERC20(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256, // minOutputTokenAmount,
        ZeroXTransformation[] memory // transformations
    ) external returns (uint256 outputTokenAmount) {
        IERC20(inputToken).safeTransferFrom(
            msg.sender,
            address(this),
            inputTokenAmount
        );

        outputTokenAmount =
            (inputTokenAmount * exchangeRateBips) /
            Constants.BASIS_POINTS_DIVISOR;
        IERC20(outputToken).safeTransfer(msg.sender, outputTokenAmount);
    }
}

