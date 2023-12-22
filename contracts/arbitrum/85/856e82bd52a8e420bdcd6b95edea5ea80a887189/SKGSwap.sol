// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./TransferHelper.sol";

abstract contract WrappedNative {
    function deposit() public payable {}
}

contract SKGSwap {
    address public constant W_NATIVE = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    ISwapRouter public immutable swapRouter;
    WrappedNative private immutable _wrappedNative;

    struct SwapParams {
        address _tokenIn;
        address[]  _tokenOutList;
        uint24[] _poolFeeList;
        uint256[] _amountInList;
        uint256[] _amountOutMinimumList;
    }

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
        _wrappedNative = WrappedNative(W_NATIVE);
    }

    function swapERC20(address tokenIn, uint256 amountInSum, uint256[] memory amountInList, address[] memory tokenOutList, uint24[] memory poolFeeList, uint256[] memory amountOutMinimumList, uint256[] memory pathsLength) external {
        _requiredCorrectArgument(amountInList, tokenOutList, poolFeeList, amountOutMinimumList, pathsLength);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInSum);
        _swap(tokenIn, amountInSum, amountInList, tokenOutList, poolFeeList, amountOutMinimumList, pathsLength);
    }

    function swapNative(uint256 amountInSum, uint256[] memory amountInList, address[] memory tokenOutList, uint24[] memory poolFeeList, uint256[] memory amountOutMinimumList, uint256[] memory pathsLength) external payable {
        _requiredCorrectArgument(amountInList, tokenOutList, poolFeeList, amountOutMinimumList, pathsLength);

        _wrappedNative.deposit{value:msg.value}();
        _swap(W_NATIVE, amountInSum, amountInList, tokenOutList, poolFeeList, amountOutMinimumList, pathsLength);
    }

    function _swap(address tokenIn, uint256 amountInSum, uint256[] memory amountInList, address[] memory tokenOutList, uint24[] memory poolFeeList, uint256[] memory amountOutMinimumList, uint256[] memory pathsLength) internal {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInSum);

        SwapParams memory _swapParams;
        _swapParams._tokenIn = tokenIn;
        _swapParams._tokenOutList = tokenOutList;
        _swapParams._poolFeeList = poolFeeList;
        _swapParams._amountInList = amountInList;
        _swapParams._amountOutMinimumList = amountOutMinimumList;

        uint256 total = amountInList.length;
        uint256 currentPath = 0;
        for (uint256 i = 0; i < total; i++) {
            uint256 pathLength = pathsLength[i];
            if (pathLength > 1) {
                _exactInput(_swapParams._tokenIn, currentPath, pathLength, _swapParams._tokenOutList, _swapParams._poolFeeList, _swapParams._amountInList[i], _swapParams._amountOutMinimumList[i]);
            } else {
                _exactInputSingle(_swapParams._tokenIn, _swapParams._tokenOutList[currentPath], _swapParams._poolFeeList[currentPath], _swapParams._amountInList[i], _swapParams._amountOutMinimumList[i]);
            }

            currentPath += pathLength;
        }
    }

    function _exactInput(address tokenIn, uint256 currentPath, uint256 pathLength, address[] memory tokenOutList, uint24[] memory poolFeeList, uint256 amountIn, uint256 amountOutMinimum) internal {
        bytes memory path = abi.encodePacked(tokenIn);

        for(uint256 j = 0; j < pathLength; j++) {
            path = abi.encodePacked(path, poolFeeList[currentPath + j], tokenOutList[currentPath + j]);
        }

        ISwapRouter.ExactInputParams memory params =
        ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        swapRouter.exactInput(params);
    }

    function _exactInputSingle(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMinimum) internal {
        ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(params);
    }

    function _requiredCorrectArgument(uint256[] memory amountInList, address[] memory tokenOutList, uint24[] memory poolFeeList, uint256[] memory amountOutMinimumList, uint256[] memory pathsLength) internal view virtual {
        require(amountInList.length > 0, "amountInList.length=0");
        require(amountInList.length <= tokenOutList.length, "tokenOutList less amountInList");
        require(amountInList.length <= poolFeeList.length, "poolFeeList less amountInList");
        require(amountInList.length == amountOutMinimumList.length, "Different length amountOutMinimumList");
        require(amountInList.length == pathsLength.length, "Different length pathsLength");

        uint256 totalPathLength = 0;
        for (uint256 i = 0; i < pathsLength.length; i++) {
            totalPathLength += pathsLength[i];
        }

        require(totalPathLength == tokenOutList.length, "tokenOutList != totalPathLength");
        require(totalPathLength == poolFeeList.length, "poolFeeList != totalPathLength");
    }
}

