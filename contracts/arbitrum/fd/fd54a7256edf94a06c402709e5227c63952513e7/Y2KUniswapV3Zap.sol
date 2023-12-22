// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {BytesLib} from "./BytesLib.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Callback} from "./IUniswapV3Callback.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IErrors} from "./IErrors.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {IPermit2} from "./IPermit2.sol";

contract Y2KUniswapV3Zap is IErrors, IUniswapV3Callback, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    using BytesLib for bytes;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128740;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    address public immutable uniswapV3Factory;
    IPermit2 public immutable permit2;

    struct SwapInputs {
        address[] path;
        uint24[] fee;
        uint256 toAmountMin;
        uint256 id;
        address vaultAddress;
        address receiver;
    }

    constructor(address _uniswapV3Factory, address _permit2) {
        if (_uniswapV3Factory == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        uniswapV3Factory = _uniswapV3Factory;
        permit2 = IPermit2(_permit2);
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    function zapIn(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fee, fromAmount);
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    function zapInPermit(
        SwapInputs calldata inputs,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(
            inputs.path,
            inputs.fee,
            transferDetails.requestedAmount
        );
        if (amountOut < inputs.toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(
            inputs.path[inputs.path.length - 1],
            inputs.id,
            amountOut,
            inputs.vaultAddress,
            inputs.receiver
        );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, uint24 fee, address tokenOut) = decodePool(_data); // TODO: Check this is in correct order

        if (msg.sender != getPool(tokenIn, tokenOut, fee))
            revert InvalidCaller();

        SafeTransferLib.safeTransfer(
            ERC20(tokenIn),
            msg.sender,
            amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta)
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }

    function _swap(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount
    ) internal returns (uint256 amountOut) {
        if (path.length > 2) {
            amountOut = _executeSwap(path[0], path[1], fromAmount, fee[0]);
            for (uint256 i = 1; i < path.length - 2; ) {
                amountOut = _executeSwap(
                    path[i],
                    path[i + 1],
                    amountOut,
                    fee[i]
                );
                unchecked {
                    i++;
                }
            }
            return
                _executeSwap(
                    path[path.length - 2],
                    path[path.length - 1],
                    amountOut,
                    fee[path.length - 2]
                );
        } else {
            return _executeSwap(path[0], path[1], fromAmount, fee[0]);
        }
    }

    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 fromAmount,
        uint24 fee
    ) private returns (uint256) {
        bool zeroForOne = tokenIn < tokenOut;
        if (zeroForOne) {
            (, int256 amountOut) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    address(this),
                    zeroForOne,
                    int256(fromAmount),
                    MIN_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        } else {
            (int256 amountOut, ) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    address(this),
                    zeroForOne,
                    int256(fromAmount),
                    MAX_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        }
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            uniswapV3Factory,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    function decodePool(
        bytes memory path
    ) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}

