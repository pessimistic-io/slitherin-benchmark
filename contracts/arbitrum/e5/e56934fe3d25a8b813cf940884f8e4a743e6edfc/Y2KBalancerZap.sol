// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IBalancerVault} from "./IBalancerVault.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IErrors} from "./IErrors.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {IPermit2} from "./IPermit2.sol";

contract Y2KBalancerZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IBalancerVault public immutable balancerVault;
    IPermit2 public immutable permit2;

    constructor(address _balancerVault, address _permit2) {
        if (_balancerVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        balancerVault = IBalancerVault(_balancerVault);
        permit2 = IPermit2(_permit2);
    }

    function zapIn(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(singleSwap.assetIn).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(singleSwap.assetIn).safeApprove(
            address(balancerVault),
            fromAmount
        );
        uint256 amountOut = balancerVault.swap(
            singleSwap,
            IBalancerVault.Funds({
                sender: address(this),
                fromInternalBalance: false,
                recipient: address(this),
                toInternalBalance: false
            }),
            toAmountMin,
            block.timestamp + 60 * 15
        );
        _deposit(singleSwap.assetOut, id, amountOut, vaultAddress, receiver);
    }

    function zapInPermit(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(balancerVault),
            transferDetails.requestedAmount
        );
        uint256 amountOut = balancerVault.swap(
            singleSwap,
            IBalancerVault.Funds({
                sender: address(this),
                fromInternalBalance: false,
                recipient: address(this),
                toInternalBalance: false
            }),
            toAmountMin,
            permit.deadline
        );
        _deposit(singleSwap.assetOut, id, amountOut, vaultAddress, receiver);
    }

    function zapInMulti(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        uint256 fromAmount = uint256(limits[0]);
        address fromToken = assets[0];
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(fromToken).safeApprove(address(balancerVault), fromAmount);
        int256[] memory assetDeltas = balancerVault.batchSwap(
            kind,
            swaps,
            assets,
            IBalancerVault.Fundmanagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limits,
            deadline
        );
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(
            assets[assets.length - 1],
            id,
            amountOut, // TODO: Could just use deconstructed amountOut as input
            vaultAddress,
            receiver
        );
    }

    function zapInMultiPermit(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(balancerVault),
            transferDetails.requestedAmount
        );
        int256[] memory assetDeltas = balancerVault.batchSwap(
            kind,
            swaps,
            assets,
            IBalancerVault.Fundmanagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limits,
            permit.deadline
        );
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(
            assets[assets.length - 1],
            id,
            amountOut, // TODO: Could just use deconstructed amountOut as input
            vaultAddress,
            receiver
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
}

