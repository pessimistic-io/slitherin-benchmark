// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {InputStream} from "./InputStream.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IPair} from "./IPair.sol";
import {IWETH} from "./IWETH.sol";
import {IStableSwapDispatcher} from "./IStableSwapDispatcher.sol";
import {IFeeSettlement} from "./IFeeSettlement.sol";
import {AdminUpgradeable} from "./AdminUpgradeable.sol";
import {Constants} from "./Constants.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IVault} from "./IVault.sol";
import {ILBPair} from "./ILBPair.sol";
import {Pausable} from "./Pausable.sol";
import {ICurveStableDispatcher} from "./ICurveStableDispatcher.sol";

contract UniversalRouter2 is ReentrancyGuard, AdminUpgradeable, Pausable {
    using SafeERC20 for IERC20;
    using SafeTransferLib for address;
    using InputStream for uint256;

    IStableSwapDispatcher public stableSwapDispatcher;
    ICurveStableDispatcher public curveStableDispatcher;
    IFeeSettlement public feeSettlement;
    address private lastCalledPool;

    error UnknownCommandCode(uint8 code);
    error UnknownPoolType(uint8 poolType);
    error MinimalInputBalanceViolation();
    error MinimalOutputBalanceViolation();
    error InvalidPool(address pool);
    error UnexpectedAddress(address addr);
    error UnexpectedUniV3Swap();
    error UnexpectedAlgebraSwap();

    event SetCurveStableDispatcher(ICurveStableDispatcher curveStableDispatcher);
    event SetStableSwapDispatcher(IStableSwapDispatcher stableSwapDispatcher);
    event SetFeeSettlement(IFeeSettlement feeSettlement);
    
    constructor(
        IStableSwapDispatcher _stableSwapDispatcher,
        ICurveStableDispatcher _curveStableDispatcher,
        IFeeSettlement _feeSettlement
    ) {
        stableSwapDispatcher = _stableSwapDispatcher;
        curveStableDispatcher = _curveStableDispatcher;
        feeSettlement = _feeSettlement;
        lastCalledPool = Constants.IMPOSSIBLE_POOL_ADDRESS;
        _initializeAdmin(msg.sender);
    }

    /// @notice To receive ETH from WETH
    receive() external payable {}

    /// @notice Set StableSwapDispatcher by admin
    /// @param _stableSwapDispatcher StableSwapDispatcher address
    function setStableSwapDispatcher(IStableSwapDispatcher _stableSwapDispatcher) external onlyAdmin {
        stableSwapDispatcher = _stableSwapDispatcher;
        emit SetStableSwapDispatcher(_stableSwapDispatcher);
    }

    /// @notice Set CurveStableDispatcher by admin
    /// @param _curveStableDispatcher CurveStableDispatcher address
    function setCurveStableDispatcher(ICurveStableDispatcher _curveStableDispatcher) external onlyAdmin {
        curveStableDispatcher = _curveStableDispatcher;
        emit SetCurveStableDispatcher(_curveStableDispatcher);
    }

    /// @notice Set FeeSettlement by admin
    /// @param _feeSettlement FeeSettlement address
    function setFeeSettlement(IFeeSettlement _feeSettlement) external onlyAdmin {
        feeSettlement = _feeSettlement;
        emit SetFeeSettlement(_feeSettlement);
    }

    /// @notice Decodes and executes the given route
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @param to Receiver address
    /// @param route The encoded route to execute with
    /// @return amountOut Actual amount of the output token
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        return processRouteInternal(tokenIn, amountIn, tokenOut, amountOutMin, to, route);
    }

    function transferValueAndprocessRoute(
        address transferValueTo,
        uint256 amountValueTransfer,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        transferValueTo.safeTransferETH(amountValueTransfer);
        return processRouteInternal(tokenIn, amountIn, tokenOut, amountOutMin, to, route);
    }

    /// @notice Decodes and executes the given route
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @param to Receiver address
    /// @param route The encoded route to execute with
    /// @return amountOut Actual amount of the output token
    function processRouteInternal(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) private returns (uint256 amountOut) {
        uint256 balanceInInitial = tokenIn == Constants.NATIVE_ADDRESS 
            ? address(this).balance 
            : IERC20(tokenIn).balanceOf(msg.sender);
        uint256 balanceOutInitial = tokenOut == Constants.NATIVE_ADDRESS 
            ? address(to).balance 
            : IERC20(tokenOut).balanceOf(to);

        uint256 stream = InputStream.createStream(route);
        while (stream.isNotEmpty()) {
            uint8 commandCode = stream.readUint8();
            if (commandCode == 1) _processMyERC20(stream);
            else if (commandCode == 2) _processUserERC20(stream, amountIn);
            else if (commandCode == 3) _processNative(stream);
            else if (commandCode == 4) _processOnePool(stream);
            else revert UnknownCommandCode(commandCode);
        }

        uint256 balanceInFinal = tokenIn == Constants.NATIVE_ADDRESS 
            ? address(this).balance 
            : IERC20(tokenIn).balanceOf(msg.sender);
        if (balanceInFinal + amountIn < balanceInInitial) revert MinimalInputBalanceViolation();

        feeSettlement.processSettlement(tokenOut, amountOutMin, msg.sender, to);

        uint256 balanceOutFinal = tokenOut == Constants.NATIVE_ADDRESS 
            ? address(to).balance 
            : IERC20(tokenOut).balanceOf(to);
        if (balanceOutFinal < balanceOutInitial + amountOutMin) revert MinimalOutputBalanceViolation();

        amountOut = balanceOutFinal - balanceOutInitial;
    }

    /// @notice Processes native coin: call swap for all pools that swap from native coin
    /// @param stream Streamed process program
    function _processNative(uint256 stream) private {
        uint256 amountTotal = address(this).balance;
        _distributeAndSwap(stream, address(this), Constants.NATIVE_ADDRESS, amountTotal);
    }

    /// @notice Processes ERC20 token from this contract balance:
    /// @notice Call swap for all pools that swap from this token
    /// @param stream Streamed process program
    function _processMyERC20(uint256 stream) private {
        address token = stream.readAddress();
        uint256 amountTotal = IERC20(token).balanceOf(address(this));
        unchecked {
            if (amountTotal > 0) amountTotal -= 1;     // slot undrain protection
        }
        _distributeAndSwap(stream, address(this), token, amountTotal);
    }

    /// @notice Processes ERC20 token from msg.sender balance:
    /// @notice Call swap for all pools that swap from this token
    /// @param stream Streamed process program
    /// @param amountTotal Amount of tokens to take from msg.sender
    function _processUserERC20(uint256 stream, uint256 amountTotal) private {
        address token = stream.readAddress();
        _distributeAndSwap(stream, msg.sender, token, amountTotal);
    }

    /// @notice Distributes amountTotal to several pools according to their shares and calls swap for each pool
    /// @param stream Streamed process program
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountTotal Total amount of tokenIn for swaps 
    function _distributeAndSwap(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountTotal
    ) private {
        uint8 num = stream.readUint8();
        for (uint256 i = 0; i < num; ++i) {
            uint16 share = stream.readUint16();
            uint256 amount = (amountTotal * share) / 65535;
            amountTotal -= amount;
            _swap(stream, from, tokenIn, amount);
        }
    }

    /// @notice Processes ERC20 token for cases when the token has only one output pool
    /// @notice In this case liquidity is already at pool balance. This is an optimization
    /// @notice Call swap for all pools that swap from this token
    /// @param stream Streamed process program
    function _processOnePool(uint256 stream) private {
        address token = stream.readAddress();
        _swap(stream, address(this), token, 0);
    }

    /// @notice Makes swap
    /// @param stream Streamed process program
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swap(uint256 stream, address from, address tokenIn, uint256 amountIn) private {
        uint8 poolType = stream.readUint8();
        if (poolType == 0) _swapUniV2(stream, from, tokenIn, amountIn);
        else if (poolType == 1) _swapUniV3(stream, from, tokenIn, amountIn);
        else if (poolType == 2) _wrapNative(stream, from, tokenIn, amountIn);
        else if (poolType == 3) _swapStableSwap(stream, from, tokenIn, amountIn);
        else if (poolType == 4) _swapGmx(stream, from, tokenIn, amountIn);
        else if (poolType == 5) _swapJoeV2(stream, from, tokenIn, amountIn);
        else if (poolType == 6) _swapAlgebra(stream, from, tokenIn, amountIn);
        else if (poolType == 7) _swapCurveStable(stream, from, tokenIn, amountIn);
        else revert UnknownPoolType(poolType);
    }

    /// @notice UniswapV2 pool swap
    /// @param stream [pool, direction, recipient]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapUniV2(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        address pool = stream.readAddress();
        uint8 direction = stream.readUint8();
        address to = stream.readAddress();

        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert InvalidPool(pool);
        (uint256 reserveIn, uint256 reserveOut) = direction == 1 
            ? (reserve0, reserve1) 
            : (reserve1, reserve0);

        if (amountIn != 0) {
            if (from == address(this)) {
                IERC20(tokenIn).safeTransfer(pool, amountIn);
            } else {
                IERC20(tokenIn).safeTransferFrom(from, pool, amountIn);
            }
        } else {
            amountIn = IERC20(tokenIn).balanceOf(pool) - reserveIn;  // tokens already were transferred
        }
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
        (uint256 amount0Out, uint256 amount1Out) = direction == 1 
            ? (uint256(0), amountOut) 
            : (amountOut, uint256(0));

        IPair(pool).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    /// @notice UniswapV3 pool swap
    /// @param stream [pool, direction, recipient]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapUniV3(
        uint256 stream,
        address from,
        address tokenIn,
        uint256 amountIn
    ) private {
        address pool = stream.readAddress();
        bool zeroForOne = stream.readUint8() > 0;
        address recipient = stream.readAddress();

        if (from != address(this)) {
            if (from !=  msg.sender) revert UnexpectedAddress(from);
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        lastCalledPool = pool;
        IUniswapV3Pool(pool).swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? Constants.MIN_SQRT_RATIO + 1 : Constants.MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );
        if (lastCalledPool != Constants.IMPOSSIBLE_POOL_ADDRESS) revert UnexpectedUniV3Swap();
    }

    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
    ) external {
        if (msg.sender != lastCalledPool) revert UnexpectedUniV3Swap();
        lastCalledPool = Constants.IMPOSSIBLE_POOL_ADDRESS;
        (address tokenIn) = abi.decode(data, (address));
        int256 amount = amount0Delta > 0 ? amount0Delta : amount1Delta;
        if (amount <= 0) revert UnexpectedUniV3Swap();
        IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount));
    }

    /// @notice Algebra pool swap
    /// @param stream [pool, direction, recipient]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapAlgebra(
        uint256 stream,
        address from,
        address tokenIn,
        uint256 amountIn
    ) private {
        address pool = stream.readAddress();
        bool zeroForOne = stream.readUint8() > 0;
        address recipient = stream.readAddress();

        if (from != address(this)) {
            if (from !=  msg.sender) revert UnexpectedAddress(from);
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        lastCalledPool = pool;
        IAlgebraPool(pool).swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? Constants.MIN_SQRT_RATIO + 1 : Constants.MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );
        if (lastCalledPool != Constants.IMPOSSIBLE_POOL_ADDRESS) revert UnexpectedUniV3Swap();
    }

    /// @notice Called to `msg.sender` after executing a swap via IAlgebraPool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be an AlgebraPool deployed by the canonical AlgebraFactory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IAlgebraPoolActions#swap call
    function algebraSwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata data
    ) external {
        if (msg.sender != lastCalledPool) revert UnexpectedAlgebraSwap();
        lastCalledPool = Constants.IMPOSSIBLE_POOL_ADDRESS;
        (address tokenIn) = abi.decode(data, (address));
        int256 amount = amount0Delta > 0 ? amount0Delta : amount1Delta;
        if (amount <= 0) revert UnexpectedAlgebraSwap();
        IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount));
    }

    /// @notice Wraps/unwraps native token
    /// @param stream [direction & fake, recipient, wrapToken?]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _wrapNative(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private {
        uint8 direction = stream.readUint8();
        address to = stream.readAddress();

        if (direction & 1 == 1) {
            address wrapToken = stream.readAddress();
            IWETH(wrapToken).deposit{value: amountIn}();
            if (to != address(this)) IERC20(wrapToken).safeTransfer(to, amountIn);
        } else {
            if (from != address(this)) IERC20(tokenIn).safeTransferFrom(from, address(this), amountIn);
            IWETH(tokenIn).withdraw(amountIn);
            to.safeTransferETH(address(this).balance);
        }
    }

    /// @notice Performs a Zenlink stable pool swap
    /// @param stream [isMetaSwap, To, [Pool, Option(isNativePool), TokenInIndex, TokenOutIndex, TokenOut]]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapStableSwap(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private {
        uint8 isMetaSwap = stream.readUint8();
        address to = stream.readAddress();
        bytes memory swapData = stream.readBytes();
        if (amountIn != 0) {
            if (from == address(this)) {
                IERC20(tokenIn).safeTransfer(address(stableSwapDispatcher), amountIn);
            } else {
                IERC20(tokenIn).safeTransferFrom(from, address(stableSwapDispatcher), amountIn);
            }
        } else {
            amountIn = IERC20(tokenIn).balanceOf(address(stableSwapDispatcher));  // tokens already were transferred
        }
        
        if (isMetaSwap == 1) {
            (address pool, uint8 tokenInIndex, uint8 tokenOutIndex, address tokenOut) = abi.decode(
                swapData, 
                (address, uint8, uint8, address)
            );
            stableSwapDispatcher.swapUnderlying(pool, tokenInIndex, tokenOutIndex, tokenIn, tokenOut, to);
        } else {
            (address pool, bool isNativePool, uint8 tokenInIndex, uint8 tokenOutIndex, address tokenOut) = abi.decode(
                swapData, 
                (address, bool, uint8, uint8, address)
            );
            stableSwapDispatcher.swap(pool, isNativePool, tokenInIndex, tokenOutIndex, tokenIn, tokenOut, to);
        }
    }

    /// @notice Performs a Curve stable pool swap
    /// @param stream [isMetaSwap, To, [Pool, Option(isNativePool), TokenInIndex, TokenOutIndex, TokenOut]]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapCurveStable(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private {
        uint8 isMetaSwap = stream.readUint8();
        address to = stream.readAddress();
        bytes memory swapData = stream.readBytes();
        if (amountIn != 0) {
            if (from == address(this)) {
                IERC20(tokenIn).safeTransfer(address(curveStableDispatcher), amountIn);
            } else {
                IERC20(tokenIn).safeTransferFrom(from, address(curveStableDispatcher), amountIn);
            }
        } else {
            amountIn = IERC20(tokenIn).balanceOf(address(curveStableDispatcher));  // tokens already were transferred
        }
        
        if (isMetaSwap == 1) {
            (address pool, int128 tokenInIndex, int128 tokenOutIndex, address tokenOut) = abi.decode(
                swapData, 
                (address, int128, int128, address)
            );
            curveStableDispatcher.exchange_underlying(pool, tokenInIndex, tokenOutIndex, tokenIn, tokenOut, to);
        } else {
            (address pool, bool isNativePool, int128 tokenInIndex, int128 tokenOutIndex, address tokenOut) = abi.decode(
                swapData, 
                (address, bool, int128, int128, address)
            );
            curveStableDispatcher.exchange(pool, isNativePool, tokenInIndex, tokenOutIndex, tokenIn, tokenOut, to);
        }
    }

    /// @notice GMX vault swap
    /// @param stream [tokenOut, receiver]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapGmx(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private {
        address vault = stream.readAddress();
        address tokenOut = stream.readAddress();
        address receiver = stream.readAddress();

        if (amountIn != 0) {
            if (from == address(this)) {
                IERC20(tokenIn).safeTransfer(vault, amountIn);
            } else {
                IERC20(tokenIn).safeTransferFrom(from, vault, amountIn);
            }
        } else {
            amountIn = IERC20(tokenIn).balanceOf(vault) - IVault(vault).tokenBalances(tokenIn);  // tokens already were transferred
        }
        IVault(vault).swap(tokenIn, tokenOut, receiver);
    }

    /// @notice Trader Joe V2 swap
    /// @param stream [pool, swapForY, receiver]
    /// @param from Where to take liquidity for swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function _swapJoeV2(
        uint256 stream, 
        address from, 
        address tokenIn, 
        uint256 amountIn
    ) private {
        address pool = stream.readAddress();
        bool swapForY = stream.readUint8() > 0;
        address recipient = stream.readAddress();

        (uint128 reserveX, uint128 reserveY) = ILBPair(pool).getReserves();
        if (reserveX == 0 || reserveY == 0) revert InvalidPool(pool);
        (uint256 reserveIn, ) = swapForY
            ? (reserveX, reserveY) 
            : (reserveY, reserveX);

        if (amountIn != 0) {
            if (from == address(this)) {
                IERC20(tokenIn).safeTransfer(pool, amountIn);
            } else {
                IERC20(tokenIn).safeTransferFrom(from, pool, amountIn);
            }
        } else {
            amountIn = IERC20(tokenIn).balanceOf(pool) - reserveIn;  // tokens already were transferred
        }

        ILBPair(pool).swap(swapForY, recipient);
    }
}

