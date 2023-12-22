// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import "./errors.sol";
import {Swap} from "./Swap.sol";
import {IAggregationRouterV4, SwapDescription} from "./IOneInch.sol";

struct AggregationRouterV4CallData {
    address caller;
    SwapDescription desc;
    bytes data;
}

contract OneInch is Swap {
    using SafeERC20 for IERC20;

    IAggregationRouterV4 public immutable ROUTER;

    constructor(IAggregationRouterV4 router) {
        ROUTER = router;
    }

    function approveTokens(address[] memory tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(address(ROUTER), 0);
            IERC20(tokens[i]).safeApprove(address(ROUTER), type(uint256).max);
        }
    }

    function swap(AggregationRouterV4CallData calldata data)
        external
        checkToken(data.desc.srcToken)
        checkToken(data.desc.dstToken)
        onlyOwner
    {
        if (data.desc.dstReceiver != owner) revert OnlyOwner();
        ROUTER.swap(data.caller, data.desc, data.data);
    }
}

