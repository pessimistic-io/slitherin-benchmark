// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";

import { IQuoterV2 } from "./IQuoterV2.sol";
import { ISwapRouter } from "./ISwapRouter.sol";

import { TransferHelper } from "./TransferHelper.sol";
import { Ownable } from "./Ownable.sol";

import { IWETH9 } from "./IWETH9.sol";
import { IBatchSwap } from "./IBatchSwap.sol";

contract BatchSwap is Ownable {
	/** Errors */
	error InsufficientAmountOut();
	error InvalidSwap();
	error SushiswapFail();
	error FeeTooHigh();
	error Locked();
	error NotLocked();

	/** Data Types */

	enum Protocol { UniswapV3, SushiSwap, WETH }

	enum Lock { __, UNLOCKED, LOCKED }

	struct Swap {
		Protocol protocol;
		address tokenA;
		address tokenB;
		uint24 poolFee;    // Only for UniswapV3
		uint256 amountIn;  // Only for first swap
	}

	/** Immutables */

	ISwapRouter public immutable uniswapRouter;          // 0xE592427A0AEce92De3Edee1F18E0157C05861564
	IQuoterV2 public immutable uniswapQuoter;            // 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
	IUniswapV2Router02 public immutable sushiswapRouter; // 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
	IWETH9 public immutable weth;    					 // 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1

	/** Storage */

	address public treasury;
	uint256 public fee;

	Lock lock;

	/** Modifiers */

	modifier useLock {
		if (lock == Lock.LOCKED) {
			revert Locked();
		}

		lock = Lock.LOCKED;

		_;

		lock = Lock.UNLOCKED;
	}

	modifier duringLock {
		if (lock == Lock.UNLOCKED) {
			revert NotLocked();
		}
		_;
	}

	/** Constructor */

	constructor(ISwapRouter _uniswapRouter, IQuoterV2 _uniswapQuoter, IUniswapV2Router02 _sushiswapRouter, IWETH9 _weth, address _treasury, uint256 _fee) {
		if(_fee > 100_000) {
			revert FeeTooHigh();
		}

		uniswapRouter = _uniswapRouter;
		uniswapQuoter = _uniswapQuoter;

		sushiswapRouter = _sushiswapRouter;

		weth = _weth;

		treasury = _treasury;
		fee = _fee;

		lock = Lock.UNLOCKED;
	}

	/** External Functions */

    function singleSwap(Swap memory swap, uint256 minAmountOut, address recipient) external payable useLock {
		if(_isWethDeposit(swap)) {
			if(msg.value != swap.amountIn) {
				revert InvalidSwap();
			}
		} else {
			if(msg.value > 0) {
				revert InvalidSwap();
			}

			TransferHelper.safeTransferFrom(swap.tokenA, msg.sender, address(this), swap.amountIn);
		}

		if(treasury != address(0) && fee != 0) {
			uint256 swapFee = swap.amountIn * fee / 1_000_000;
			if(_isWethDeposit(swap)) {
				TransferHelper.safeTransferETH(treasury, swapFee);
			} else {
				TransferHelper.safeTransfer(swap.tokenA, treasury, swapFee);
			}
			swap.amountIn -= swapFee;
		}

		uint256 amountOut;
		if(swap.protocol == Protocol.UniswapV3) {
			amountOut = _uniswapSwap(swap, recipient);
		} else if(swap.protocol == Protocol.SushiSwap) {
			amountOut = _sushiswapSwap(swap, recipient);
		} else {
			amountOut = _wethSwap(swap, recipient);
		}

		if(amountOut < minAmountOut) {
			revert InsufficientAmountOut();
		}
	}

    function batchSwap(Swap[] memory swap, uint256 minAmountOut, address recipient) external payable useLock {
        if (swap.length <= 1) {
			revert InvalidSwap();
		}

		if(_isWethDeposit(swap[0])) {
			if(msg.value != swap[0].amountIn) {
				revert InvalidSwap();
			}
		} else {
			if(msg.value > 0) {
				revert InvalidSwap();
			}

			TransferHelper.safeTransferFrom(swap[0].tokenA, msg.sender, address(this), swap[0].amountIn);
		}

		if(treasury != address(0) && fee != 0) {
			uint256 swapFee = swap[0].amountIn * fee / 1_000_000;
			if(_isWethDeposit(swap[0])) {
				TransferHelper.safeTransferETH(treasury, swapFee);
			} else {
				TransferHelper.safeTransfer(swap[0].tokenA, treasury, swapFee);
			}
			swap[0].amountIn -= swapFee;
		}

		uint256 lastAmountOut;
        for(uint256 i = 0; i < swap.length; i++) {
			if(i != 0) {
				swap[i].amountIn = lastAmountOut;
			}

		    if(swap[i].protocol == Protocol.UniswapV3) {
		    	lastAmountOut = _uniswapSwap(swap[i], i == swap.length - 1 ? recipient : address(this));
		    } else if(swap[i].protocol == Protocol.SushiSwap) {
		    	lastAmountOut = _sushiswapSwap(swap[i], i == swap.length - 1 ? recipient : address(this));
		    } else {
				lastAmountOut = _wethSwap(swap[i], i == swap.length - 1 ? recipient : address(this));
			}
        }

		if(lastAmountOut < minAmountOut) {
			revert InsufficientAmountOut();
		}
	}

	/** View Functions */

    function singleSwapEstimateAmountOut(Swap memory swap) external returns(uint256) {
		if(treasury != address(0) && fee != 0) {
			uint256 swapFee = swap.amountIn * fee / 1_000_000;
			swap.amountIn -= swapFee;
		}

		uint256 amountOut;
		if(swap.protocol == Protocol.UniswapV3) {
			amountOut = _uniswapEstimateAmountOut(swap);
		} else if(swap.protocol == Protocol.SushiSwap) {
			amountOut = _sushiswapEstimateAmountOut(swap);
		} else {
			amountOut = swap.amountIn; // WETH -> ETH is 1 -> 1
		}

		return amountOut;
	}

    function batchSwapEstimateAmountOut(Swap[] memory swap) external returns(uint256) {
        if (swap.length <= 1) {
			revert InvalidSwap();
		}

		if(treasury != address(0) && fee != 0) {
			uint256 swapFee = swap[0].amountIn * fee / 1_000_000;
			swap[0].amountIn -= swapFee;
		}

		uint256 lastAmountOut;
        for(uint256 i = 0; i < swap.length; i++) {
			if(i != 0) {
				swap[i].amountIn = lastAmountOut;
			}

		    if(swap[i].protocol == Protocol.UniswapV3) {
		    	lastAmountOut = _uniswapEstimateAmountOut(swap[i]);
		    } else if(swap[i].protocol == Protocol.SushiSwap) {
		    	lastAmountOut = _sushiswapEstimateAmountOut(swap[i]);
		    } else {
				lastAmountOut = swap[i].amountIn; // WETH -> ETH is 1 -> 1
			}
        }

		return lastAmountOut;
	}

	/** Internal Functions */

	function _uniswapSwap(Swap memory swap, address recipient) internal returns(uint256 amountOut) {
        return uniswapRouter.exactInputSingle(
			ISwapRouter.ExactInputSingleParams({
                tokenIn: swap.tokenA,
                tokenOut: swap.tokenB,
                fee: swap.poolFee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: swap.amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
		);
	}

	function _sushiswapSwap(Swap memory swap, address recipient) internal returns(uint256 amountOut) {
		address[] memory path = new address[](2);
		path[0] = swap.tokenA;
		path[1] = swap.tokenB;

        sushiswapRouter.swapExactTokensForTokens(swap.amountIn, 0, path, recipient, block.timestamp);

		bool revertFlag;
		assembly {
			if iszero(eq(returndatasize(), 0x80)) {
				revertFlag := 1
			}
		}
		if(revertFlag) revert SushiswapFail();

		assembly {
			returndatacopy(0x20, 0x60, 0x20) // Copy the `0x60-0x7f` bytes from the returndata (last amount out from the array) to the `0x20-0x3f` "scratch space" memory location
			amountOut := mload(0x20)	     // Copy the saved bytes into `amountOut`
		}
	}

	function _wethSwap(Swap memory swap, address recipient) internal returns(uint256 amountOut) {
		if(swap.tokenA == address(0)) {
			// ETH -> WETH
			if(swap.tokenB != address(weth)) {
				revert InvalidSwap();
			}

			weth.deposit{ value: swap.amountIn }();

			if(recipient != address(this)) {
				TransferHelper.safeTransfer(address(weth), recipient, swap.amountIn);
			}
		} else if(swap.tokenA == address(weth)) {
			// WETH -> ETH
			if(swap.tokenB != address(0)) {
				revert InvalidSwap();
			}

			weth.withdraw(swap.amountIn);

			if(recipient != address(this)) {
				TransferHelper.safeTransferETH(recipient, swap.amountIn);
			}
		} else {
			revert InvalidSwap();
		}
		return swap.amountIn;
	}

	function _uniswapEstimateAmountOut(Swap memory swap) internal returns(uint256) {
		(uint256 amountOut,,,) = uniswapQuoter.quoteExactInput(abi.encodePacked(swap.tokenA, swap.poolFee, swap.tokenB), swap.amountIn);
		return amountOut;
	}

	function _sushiswapEstimateAmountOut(Swap memory swap) internal view returns(uint256 amountOut) {
		address[] memory path = new address[](2);
		path[0] = swap.tokenA;
		path[1] = swap.tokenB;

		sushiswapRouter.getAmountsOut(swap.amountIn, path);

		bool revertFlag;
		assembly {
			if iszero(eq(returndatasize(), 0x80)) {
				revertFlag := 1
			}
		}
		if(revertFlag) revert SushiswapFail();

		assembly {
			returndatacopy(0x20, 0x60, 0x20) // Copy the `0x60-0x7f` bytes from the returndata (last address) to the `0x20-0x3f` "scratch space" memory location
			amountOut := mload(0x20)	     // Copy the saved bytes into `amountOut`
		}
	}

	function _isWethDeposit(Swap memory swap) internal pure returns(bool) {
		return swap.protocol == Protocol.WETH && swap.tokenA == address(0);
	}

	/** Owner Only Functions */

	function approveRouters(address[] calldata tokens) external onlyOwner {
		for(uint256 i = 0; i < tokens.length; i++) {
			TransferHelper.safeApprove(tokens[i], address(uniswapRouter), type(uint256).max);
			TransferHelper.safeApprove(tokens[i], address(sushiswapRouter), type(uint256).max);
		}
	}

	function rescueToken(address token, uint256 value) external onlyOwner {
		TransferHelper.safeTransfer(token, msg.sender, value);
	}

	function rescueETH(uint256 value) external onlyOwner {
		TransferHelper.safeTransferETH(msg.sender, value);
	}

	function setFee(uint256 _fee) external onlyOwner {
		if(_fee > 100_000) {
			revert FeeTooHigh();
		}
		fee = _fee;
	}

	function setTreasury(address _treasury) external onlyOwner {
		treasury = _treasury;
	}

	/** Receive */

	receive() external payable duringLock {}
}
