// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import { IHyphenRouter } from "./IHyphenRouter.sol";
import "./DataTypes.sol";
import "./BaseTrade.sol";
import "./ReentrancyGuard.sol";

contract SwitchHyphen is BaseTrade, ReentrancyGuard {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;
    address public hyphenRouter;

    struct TransferArgsHyphen {
        address fromToken;
        address destToken;
        address payable recipient;
        address partner;
        uint256 amount;
        uint256 estimatedDstTokenAmount;
        uint16  dstChainId;
        bytes32 id;
        bytes32 bridge;
    }

    event HyphenRouterSet(address hyphenRouter);

    constructor(
        address _switchEventAddress,
        address _hyphenRouter
    ) BaseTrade(_switchEventAddress)
        public
    {
        hyphenRouter = _hyphenRouter;
    }

    function setHyphenRouter(address _hyphenRouter) external onlyOwner {
        hyphenRouter = _hyphenRouter;
        emit HyphenRouterSet(_hyphenRouter);
    }

    function transferByHyphen(
        TransferArgsHyphen calldata transferArgs
    )
        external
        payable
        nonReentrant
    {
        require(transferArgs.recipient == msg.sender, "The recipient must be equal to caller");
        require(transferArgs.amount > 0, "The amount must be greater than zero");
        require(block.chainid != transferArgs.dstChainId, "Cannot bridge to same network");

        IERC20(transferArgs.fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(IERC20(transferArgs.fromToken), transferArgs.amount, transferArgs.partner);
        bool isNative = IERC20(transferArgs.fromToken).isETH();
        if (isNative) {
            IHyphenRouter(hyphenRouter).depositNative{ value: amountAfterFee }(
                transferArgs.recipient,
                transferArgs.dstChainId,
                "SWING"
            );
        } else {
            // Give Hyphen bridge approval
            uint256 approvedAmount = IERC20(transferArgs.fromToken).allowance(address(this), hyphenRouter);
            if (approvedAmount < amountAfterFee) {
                IERC20(transferArgs.fromToken).safeIncreaseAllowance(hyphenRouter, amountAfterFee - approvedAmount);
            }

            IHyphenRouter(hyphenRouter).depositErc20(
                transferArgs.dstChainId,
                transferArgs.fromToken,
                transferArgs.recipient,
                amountAfterFee,
                "SWING"
            );
        }

        _emitCrossChainTransferRequest(transferArgs, bytes32(0), amountAfterFee, msg.sender, DataTypes.SwapStatus.Succeeded);
    }

    function _emitCrossChainTransferRequest(TransferArgsHyphen calldata transferArgs, bytes32 transferId, uint256 returnAmount, address sender, DataTypes.SwapStatus status) internal {
        switchEvent.emitCrosschainSwapRequest(
            transferArgs.id,
            transferId,
            transferArgs.bridge,
            sender,
            transferArgs.fromToken,
            transferArgs.fromToken,
            transferArgs.destToken,
            transferArgs.amount,
            returnAmount,
            transferArgs.estimatedDstTokenAmount,
            status
        );
    }
}
