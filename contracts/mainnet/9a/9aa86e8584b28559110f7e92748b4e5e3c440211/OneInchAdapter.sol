//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGatewayRegistry} from "./IGatewayRegistry.sol";
import {IERC20} from "./IERC20.sol";
import {Context} from "./Context.sol";
import {Payment, FEE_CURRENCY} from "./Payment.sol";

struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
}

interface OneInch {
    function swap(
        address caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256);

    function unoswap(
        IERC20 srcToken,
        uint256 _amount,
        uint256 minReturn,
        bytes32[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function uniswapV3Swap(
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function uniswapV3SwapTo(
        address payable recipient,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function clipperSwap(
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) external payable returns (uint256 returnAmount);

    function clipperSwapTo(
        address payable recipient,
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) external payable returns (uint256 returnAmount);
}

contract OneInchAdapter is Context, Payment {
    OneInch public oneInch;

    constructor(OneInch oneInch_) {
        oneInch = oneInch_;
    }

    function swap(
        address caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) public payable returns (uint256) {
        uint256 amount;
        if (address(desc.srcToken) == FEE_CURRENCY) {
            amount = msg.value;
        } else {
            amount = desc.srcToken.allowance(_msgSender(), address(this));
            desc.srcToken.approve(address(oneInch), amount);
        }
        acceptPayment(address(desc.srcToken), amount);

        return
            oneInch.swap{value: msg.value}(
                caller,
                SwapDescription({
                    srcToken: desc.srcToken,
                    dstToken: desc.dstToken,
                    srcReceiver: desc.srcReceiver,
                    dstReceiver: desc.dstReceiver == address(0x0)
                        ? payable(_msgSender())
                        : desc.dstReceiver,
                    amount: amount,
                    minReturnAmount: desc.minReturnAmount,
                    flags: desc.flags,
                    permit: desc.permit
                }),
                data
            );
    }

    function unoswap(
        IERC20 srcToken,
        uint256 _amount,
        uint256 minReturn,
        bytes32[] calldata pools
    ) public payable returns (uint256 returnAmount) {
        uint256 approvedAmount;
        if (
            address(srcToken) == FEE_CURRENCY ||
            address(srcToken) == address(0x0)
        ) {
            approvedAmount = msg.value;
        } else {
            approvedAmount = srcToken.allowance(_msgSender(), address(this));
            srcToken.approve(address(oneInch), approvedAmount);
        }
        acceptPayment(address(srcToken), approvedAmount);

        return oneInch.unoswap(srcToken, approvedAmount, minReturn, pools);
    }

    function uniswapV3Swap(
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount) {
        return uniswapV3SwapTo(payable(_msgSender()), amount, minReturn, pools);
    }

    function uniswapV3SwapTo(
        address payable recipient,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) public payable returns (uint256 returnAmount) {}

    function clipperSwap(
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) external payable returns (uint256 returnAmount) {
        return
            clipperSwapTo(
                payable(_msgSender()),
                srcToken,
                dstToken,
                amount,
                minReturn
            );
    }

    function clipperSwapTo(
        address payable recipient,
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) public payable returns (uint256 returnAmount) {}
}

