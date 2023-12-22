// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IErrors} from "./IErrors.sol";
import {ICurvePair} from "./ICurvePair.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {IPermit2} from "./IPermit2.sol";

contract Y2KCurveZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    address public immutable wethAddress;
    IPermit2 public immutable permit2;

    // NOTE: Inputs for permitMulti need to be struct to avoid stack too deep
    struct MultiSwapInfo {
        address[] path;
        address[] pools;
        uint256[] iValues;
        uint256[] jValues;
        uint256 toAmountMin;
        address vaultAddress;
        address receiver;
    }

    constructor(address _wethAddress, address _permit2) {
        if (_wethAddress == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        wethAddress = _wethAddress;
        permit2 = IPermit2(_permit2);
    }

    function zapIn(
        address fromToken,
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external payable {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut;
        if (toToken == wethAddress) {
            amountOut = _swapEth(
                fromToken,
                toToken,
                pool,
                i,
                j,
                fromAmount,
                toAmountMin
            );
        } else {
            amountOut = _swap(
                fromToken,
                toToken,
                pool,
                int128(int256(i)),
                int128(int256(j)),
                fromAmount,
                toAmountMin
            );
        }
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id, vaultAddress, receiver);
    }

    function zapInPermit(
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut;
        if (toToken == wethAddress) {
            amountOut = _swapEth(
                permit.permitted.token,
                toToken,
                pool,
                i,
                j,
                transferDetails.requestedAmount,
                toAmountMin
            );
        } else {
            amountOut = _swap(
                permit.permitted.token,
                toToken,
                pool,
                int128(int256(i)),
                int128(int256(j)),
                transferDetails.requestedAmount,
                toAmountMin
            );
        }
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id, vaultAddress, receiver);
    }

    function zapInMulti(
        uint256 fromAmount,
        uint256 id,
        MultiSwapInfo calldata multiSwapInfo
    ) external {
        ERC20(multiSwapInfo.path[0]).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut = _multiSwap(
            multiSwapInfo.path,
            multiSwapInfo.pools,
            multiSwapInfo.iValues,
            multiSwapInfo.jValues,
            fromAmount,
            multiSwapInfo.toAmountMin
        );
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress,
            multiSwapInfo.receiver
        );
    }

    function zapInMultiPermit(
        uint256 id,
        MultiSwapInfo calldata multiSwapInfo,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _multiSwap(
            multiSwapInfo.path,
            multiSwapInfo.pools,
            multiSwapInfo.iValues,
            multiSwapInfo.jValues,
            transferDetails.requestedAmount,
            multiSwapInfo.toAmountMin
        );
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress,
            multiSwapInfo.receiver
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _multiSwap(
        address[] memory path,
        address[] memory pools,
        uint256[] memory iValues,
        uint256[] memory jValues,
        uint256 fromAmount,
        uint256 toAmountMin
    ) private returns (uint256 amountOut) {
        amountOut = fromAmount;
        for (uint256 i = 0; i < pools.length; ) {
            if (path[i + 1] != wethAddress) {
                amountOut = _swap(
                    path[i],
                    path[i + 1],
                    pools[i],
                    int128(int256(iValues[i])),
                    int128(int256(jValues[i])),
                    amountOut,
                    i == pools.length - 1 ? toAmountMin : 0
                );
            } else {
                amountOut = _swapEth(
                    path[i],
                    wethAddress,
                    pools[i],
                    iValues[i],
                    jValues[i],
                    amountOut,
                    i == pools.length - 1 ? toAmountMin : 0
                );
            }
            unchecked {
                i++;
            }
        }
        if (amountOut == 0) revert InvalidOutput();
    }

    function _swap(
        address fromToken,
        address toToken,
        address pool,
        int128 i,
        int128 j,
        uint256 fromAmount,
        uint256 toAmountMin
    ) private returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountMin);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }

    function _swapEth(
        address fromToken,
        address toToken,
        address pool,
        uint256 i,
        uint256 j,
        uint256 fromAmount,
        uint256 toAmountMin
    ) private returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountMin, false);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }

    function _deposit(
        address fromToken,
        uint256 amountIn,
        uint256 id,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }
}

