// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./Switch.sol";
import { IDlnSource } from "./IDlnSource.sol";
import "./DataTypes.sol";

contract SwitchDln is Switch {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;
    address public dlnSource;

    struct SwapArgsDln {
        DataTypes.SwapInfo srcSwap;
        DataTypes.SwapInfo dstSwap;
        address payable recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 expectedReturn;
        uint256 minReturn;
        uint256 estimatedDstTokenAmount;
        uint nativeFee;
        bool useParaswap;
        bytes affiliateFee;
        bytes permitEnvelope;
        bytes srcParaswapData;
        uint256[] srcDistribution;
        uint32 referralCode;
        bytes32 id;
        bytes32 bridge;
        IDlnSource.OrderCreation orderCreation;
    }

    struct TransferArgsDln {
        address fromToken;
        address destToken;
        address payable recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 estimatedDstTokenAmount;
        uint nativeFee;
        bytes affiliateFee;
        bytes permitEnvelope;
        uint32 referralCode;
        bytes32 id;
        bytes32 bridge;
        IDlnSource.OrderCreation orderCreation;
    }

    event DlnSourceSet(address dlnSource);

    constructor(
        address _weth,
        address _otherToken,
        uint256 _pathCount,
        uint256 _pathSplit,
        address[] memory _factories,
        address[] memory _switchViewAndEventAddresses,
        address _paraswapProxy,
        address _augustusSwapper,
        address _feeCollector,
        address _dlnSource
    ) Switch(
        _weth,
        _otherToken,
        _pathCount,
        _pathSplit,
        _factories,
        _switchViewAndEventAddresses[0],
        _switchViewAndEventAddresses[1],
        _paraswapProxy,
        _augustusSwapper,
        _feeCollector
    )
        public
    {
        dlnSource = _dlnSource;
    }

    function setDlnSource(address _dlnSource) external onlyOwner {
        dlnSource = _dlnSource;
        emit DlnSourceSet(_dlnSource);
    }

    function transferByDln(
        TransferArgsDln calldata transferArgs
    )
        external
        payable
        nonReentrant
        returns (bytes32)
    {
        require(transferArgs.amount > 0, "The amount must be greater than zero");
        // getting the protocol fee
        uint protocolFee = IDlnSource(dlnSource).globalFixedNativeFee();
        require(transferArgs.nativeFee >= protocolFee, "native fee is not enough");

        address fromToken = transferArgs.fromToken;
        IERC20(fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(fromToken),
            transferArgs.amount,
            transferArgs.partner,
            transferArgs.partnerFeeRate
        );

        bool isNative = IERC20(fromToken).isETH();
        if (!isNative) {
            IERC20(fromToken).universalApprove(dlnSource, amountAfterFee);
        }

        bytes32 orderId= IDlnSource(dlnSource).createOrder{ value: transferArgs.nativeFee }(
            IDlnSource.OrderCreation({
                giveTokenAddress: transferArgs.orderCreation.giveTokenAddress,
                giveAmount: transferArgs.orderCreation.giveAmount,
                takeTokenAddress: transferArgs.orderCreation.takeTokenAddress,
                takeAmount: transferArgs.orderCreation.takeAmount,
                takeChainId: transferArgs.orderCreation.takeChainId,
                receiverDst: transferArgs.orderCreation.receiverDst,
                givePatchAuthoritySrc: transferArgs.orderCreation.givePatchAuthoritySrc,
                orderAuthorityAddressDst: transferArgs.orderCreation.orderAuthorityAddressDst,
                allowedTakerDst: transferArgs.orderCreation.allowedTakerDst,
                externalCall: transferArgs.orderCreation.externalCall,
                allowedCancelBeneficiarySrc: transferArgs.orderCreation.allowedCancelBeneficiarySrc
            }),
            transferArgs.affiliateFee,
            transferArgs.referralCode,
            transferArgs.permitEnvelope
        );

        _emitCrossChainTransferRequest(
            transferArgs,
            orderId,
            amountAfterFee,
            msg.sender,
            DataTypes.SwapStatus.Succeeded
        );

        return orderId;
    }

    function swapByDln(
        SwapArgsDln calldata swapArgs
    )
        external
        payable
        nonReentrant
        returns (bytes32)
    {
        require(swapArgs.expectedReturn >= swapArgs.minReturn, "expectedReturn must be equal or larger than minReturn");
        // getting the protocol fee
        uint protocolFee = IDlnSource(dlnSource).globalFixedNativeFee();
        require(swapArgs.nativeFee >= protocolFee, "native fee is not enough");

        IERC20(swapArgs.srcSwap.srcToken).universalTransferFrom(msg.sender, address(this), swapArgs.amount);
        uint256 returnAmount = 0;
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(swapArgs.srcSwap.srcToken),
            swapArgs.amount,
            swapArgs.partner,
            swapArgs.partnerFeeRate
        );

        // check fromToken is same or not destToken
        if (swapArgs.srcSwap.srcToken == swapArgs.srcSwap.dstToken) {
            returnAmount = amountAfterFee;
        } else {
            if (swapArgs.useParaswap) {
                returnAmount = _swapFromParaswap(swapArgs, swapArgs.srcParaswapData, amountAfterFee);
            } else {
                returnAmount = _swapFromAggregator(swapArgs, amountAfterFee);
            }
        }
        require(returnAmount >= swapArgs.minReturn, "return amount was not enough");

        IERC20(swapArgs.srcSwap.dstToken).universalApprove(dlnSource, returnAmount);

        bytes32 orderId= IDlnSource(dlnSource).createOrder{ value: swapArgs.nativeFee }(
            IDlnSource.OrderCreation({
                giveTokenAddress: swapArgs.orderCreation.giveTokenAddress,
                giveAmount: swapArgs.orderCreation.giveAmount,
                takeTokenAddress: swapArgs.orderCreation.takeTokenAddress,
                takeAmount: swapArgs.orderCreation.takeAmount,
                takeChainId: swapArgs.orderCreation.takeChainId,
                receiverDst: swapArgs.orderCreation.receiverDst,
                givePatchAuthoritySrc: swapArgs.orderCreation.givePatchAuthoritySrc,
                orderAuthorityAddressDst: swapArgs.orderCreation.orderAuthorityAddressDst,
                allowedTakerDst: swapArgs.orderCreation.allowedTakerDst,
                externalCall: swapArgs.orderCreation.externalCall,
                allowedCancelBeneficiarySrc: swapArgs.orderCreation.allowedCancelBeneficiarySrc
            }),
            swapArgs.affiliateFee,
            swapArgs.referralCode,
            swapArgs.permitEnvelope
        );

        _emitCrossChainSwapRequest(
            swapArgs,
            orderId,
            returnAmount,
            msg.sender
        );

        return orderId;
    }

    function _swapFromAggregator(
        SwapArgsDln calldata swapArgs,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        uint256 parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint i = 0; i < swapArgs.srcDistribution.length; i++) {
            if (swapArgs.srcDistribution[i] > 0) {
                parts += swapArgs.srcDistribution[i];
                lastNonZeroIndex = i;
            }
        }

        require(parts > 0, "invalid distribution param");
        returnAmount = _swapInternalForSingleSwap(
            swapArgs.srcDistribution,
            amount,
            parts,
            lastNonZeroIndex,
            IERC20(swapArgs.srcSwap.srcToken),
            IERC20(swapArgs.srcSwap.dstToken)
        );
        switchEvent.emitSwapped(
            msg.sender,
            address(this),
            IERC20(swapArgs.srcSwap.srcToken),
            IERC20(swapArgs.srcSwap.dstToken),
            amount,
            returnAmount,
            0
        );
    }

    function _swapFromParaswap(
        SwapArgsDln calldata swapArgs,
        bytes calldata callData,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        returnAmount = _swapInternalWithParaSwap(
            IERC20(swapArgs.srcSwap.srcToken),
            IERC20(swapArgs.srcSwap.dstToken),
            amount,
            callData
        );
    }

    function _emitCrossChainTransferRequest(
        TransferArgsDln calldata transferArgs,
        bytes32 orderId,
        uint256 returnAmount,
        address sender,
        DataTypes.SwapStatus status
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            transferArgs.id,
            orderId,
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

    function _emitCrossChainSwapRequest(
        SwapArgsDln calldata swapArgs,
        bytes32 orderId,
        uint256 returnAmount,
        address sender
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            swapArgs.id,
            orderId,
            swapArgs.bridge,
            sender,
            swapArgs.srcSwap.srcToken,
            swapArgs.srcSwap.dstToken,
            swapArgs.dstSwap.dstToken,
            swapArgs.amount,
            returnAmount,
            swapArgs.estimatedDstTokenAmount,
            DataTypes.SwapStatus.Succeeded
        );
    }
}

