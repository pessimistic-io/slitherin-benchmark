// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IGMXVault} from "./IGMXVault.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IErrors} from "./IErrors.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {IPermit2} from "./IPermit2.sol";

contract Y2KGMXZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IGMXVault public immutable gmxVault;
    IPermit2 public immutable permit2;

    constructor(address _gmxVault, address _permit2) {
        if (_gmxVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        gmxVault = IGMXVault(_gmxVault);
        permit2 = IPermit2(_permit2);
    }

    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(path[0]).safeTransferFrom(
            msg.sender,
            address(gmxVault),
            fromAmount
        );
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    function zapInPermit(
        address[] calldata path,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    ////////////////////////////////////////
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
        uint256 toAmountMin
    ) private returns (uint256 amountOut) {
        amountOut = gmxVault.swap(path[0], path[1], address(this));
        if (path.length == 3) {
            ERC20(path[1]).safeTransfer(address(gmxVault), amountOut);
            amountOut = gmxVault.swap(path[1], path[2], address(this));
        }
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
    }
}

