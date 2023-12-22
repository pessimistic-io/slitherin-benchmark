// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./Switch.sol";
import { IConnext } from "./IConnext.sol";
import "./DataTypes.sol";

contract SwitchConnextSender is Switch {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;

    address public connext;
    address public nativeWrap;

    struct ConnextSwapRequest {
        bytes32 id;
        bytes32 bridge;
        address srcToken;
        address bridgeToken;
        address dstToken;
        address recipient;
        uint256 srcAmount;
        uint256 bridgeDstAmount;
        uint256 estimatedDstAmount;
        DataTypes.ParaswapUsageStatus paraswapUsageStatus;
        uint256[] dstDistribution;
        bytes dstParaswapData;
    }

    struct SwapArgsConnext {
        DataTypes.SwapInfo srcSwap;
        DataTypes.SwapInfo dstSwap;
        address payable recipient;
        address callTo;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 minSrcReturn;
        uint256 bridgeDstAmount;
        uint256 estimatedDstTokenAmount;
        uint256 relayerFee;
        uint256 slippage;
        uint256[] srcDistribution;
        uint256[] dstDistribution;
        uint32  dstChainDomainId;
        bytes32 id;
        bytes32 bridge;
        bytes srcParaswapData;
        bytes dstParaswapData;
        DataTypes.ParaswapUsageStatus paraswapUsageStatus;
    }

    struct TransferArgsConnext {
        address fromToken;
        address destToken;
        address payable recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 bridgeDstAmount;
        uint256 relayerFee;
        uint256 slippage;
        uint32 dstChainDomainId;
        bytes32 id;
        bytes32 bridge;
    }

    event ConnextRouterSet(address connext);
    event NativeWrapSet(address _nativeWrap);

    constructor(
        address _weth,
        address _otherToken,
        uint256[] memory _pathCountAndSplit,
        address[] memory _factories,
        address[] memory _switchViewAndEventAddresses,
        address _connext,
        address _paraswapProxy,
        address _augustusSwapper,
        address _feeCollector
    ) Switch(
        _weth,
        _otherToken,
        _pathCountAndSplit[0],
        _pathCountAndSplit[1],
        _factories,
        _switchViewAndEventAddresses[0],
        _switchViewAndEventAddresses[1],
        _paraswapProxy,
        _augustusSwapper,
        _feeCollector
    )
        public
    {
        connext = _connext;
        nativeWrap = _weth;
    }

    function setConnextRouter(address _newConnext) external onlyOwner {
        connext = _newConnext;
        emit ConnextRouterSet(_newConnext);
    }

    function setNativeWrap(address _newNativeWrap) external onlyOwner {
        nativeWrap = _newNativeWrap;
        emit NativeWrapSet(nativeWrap);
    }

    function transferByConnext(
        TransferArgsConnext calldata transferArgs
    )
        external
        payable
        nonReentrant
    {
        IERC20(transferArgs.fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(transferArgs.fromToken),
            transferArgs.amount,
            transferArgs.partner,
            transferArgs.partnerFeeRate
        );

        bool isNative = IERC20(transferArgs.fromToken).isETH();
        if (isNative) {
            require(msg.value >= transferArgs.amount + transferArgs.relayerFee, 'native token is not enough');
            require(nativeWrap != address(0), 'native wrap address should not be zero');
            weth.deposit{value: amountAfterFee}();
            weth.approve(address(connext), amountAfterFee);
        } else {
            require(msg.value >= transferArgs.relayerFee, 'native token is not enough');
            IERC20(transferArgs.fromToken).universalApprove(connext, amountAfterFee);
        }

        IConnext(connext).xcall{ value: transferArgs.relayerFee }(
            transferArgs.dstChainDomainId,
            transferArgs.recipient,
            isNative ? nativeWrap : transferArgs.fromToken,
            transferArgs.recipient,
            amountAfterFee,
            transferArgs.slippage,
            bytes("")
        );

        _emitCrossChainTransferRequest(
            transferArgs,
            bytes32(0),
            amountAfterFee,
            msg.sender,
            DataTypes.SwapStatus.Succeeded
        );
    }

    function swapByConnext(
        SwapArgsConnext calldata swapArgs
    )
        external
        payable
        nonReentrant
    {
        IERC20(swapArgs.srcSwap.srcToken).universalTransferFrom(msg.sender, address(this), swapArgs.amount);

        uint256 returnAmount = 0;
        uint256 amountAfterFee = _getAmountAfterFee(
            IERC20(swapArgs.srcSwap.srcToken),
            swapArgs.amount,
            swapArgs.partner,
            swapArgs.partnerFeeRate
        );
        bool bridgeTokenIsNative = false;

        if ((IERC20(swapArgs.srcSwap.srcToken).isETH() && IERC20(swapArgs.srcSwap.dstToken).isETH()) ||
            (IERC20(swapArgs.srcSwap.srcToken).isETH() && (swapArgs.srcSwap.dstToken == nativeWrap))
        ) {
            require(nativeWrap != address(0), 'native wrap address should not be zero');
            weth.deposit{value: amountAfterFee}();
            weth.approve(address(connext), amountAfterFee);
            bridgeTokenIsNative = true;
        }
        if (swapArgs.srcSwap.srcToken == nativeWrap && IERC20(swapArgs.srcSwap.dstToken).isETH()) {
            bridgeTokenIsNative = true;
        }

        bytes memory message = abi.encode(
            ConnextSwapRequest({
                id: swapArgs.id,
                bridge: swapArgs.bridge,
                srcToken: swapArgs.srcSwap.srcToken,
                bridgeToken: swapArgs.dstSwap.srcToken,
                dstToken: swapArgs.dstSwap.dstToken,
                recipient: swapArgs.recipient,
                srcAmount: amountAfterFee,
                dstDistribution: swapArgs.dstDistribution,
                dstParaswapData: swapArgs.dstParaswapData,
                paraswapUsageStatus: swapArgs.paraswapUsageStatus,
                bridgeDstAmount: swapArgs.bridgeDstAmount,
                estimatedDstAmount: swapArgs.estimatedDstTokenAmount
            })
        );

        if (swapArgs.srcSwap.srcToken == swapArgs.srcSwap.dstToken || bridgeTokenIsNative) {
            returnAmount = amountAfterFee;
        } else {
            if ((swapArgs.paraswapUsageStatus == DataTypes.ParaswapUsageStatus.OnSrcChain) ||
                (swapArgs.paraswapUsageStatus == DataTypes.ParaswapUsageStatus.Both)) {
                returnAmount = _swapFromParaswap(swapArgs, amountAfterFee);
            } else {
                (returnAmount, ) = _swapBeforeConnext(swapArgs, amountAfterFee);
            }
            if (IERC20(swapArgs.srcSwap.dstToken).isETH()) {
                weth.deposit{value: returnAmount}();
                weth.approve(address(connext), returnAmount);
            }
        }
        require(returnAmount >= swapArgs.minSrcReturn, "return amount was not enough");

        if (IERC20(swapArgs.srcSwap.srcToken).isETH()) {
            require(msg.value >= swapArgs.amount + swapArgs.relayerFee, 'native token is not enough');
        } else {
            require(msg.value >= swapArgs.relayerFee, 'native token is not enough');
        }

        if (!IERC20(swapArgs.srcSwap.dstToken).isETH()) {
            IERC20(swapArgs.srcSwap.dstToken).universalApprove(connext, amountAfterFee);
        }

        IConnext(connext).xcall{ value: swapArgs.relayerFee }(
            swapArgs.dstChainDomainId,
            swapArgs.recipient,
            bridgeTokenIsNative ? nativeWrap : swapArgs.srcSwap.dstToken,
            swapArgs.callTo,
            returnAmount,
            swapArgs.slippage,
            message
        );

        _emitCrossChainSwapRequest(swapArgs, bytes32(0), returnAmount, msg.sender, DataTypes.SwapStatus.Succeeded);
    }
    
    function _swapBeforeConnext(
        SwapArgsConnext calldata swapArgs,
        uint256 amount
    )
        private
        returns
    (
        uint256 returnAmount,
        uint256 parts
    )
    {
        parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint i = 0; i < swapArgs.srcDistribution.length; i++) {
            if (swapArgs.srcDistribution[i] > 0) {
                parts += swapArgs.srcDistribution[i];
                lastNonZeroIndex = i;
            }
        }

        require(parts > 0, "invalid distribution param");

        // break function to avoid stack too deep error
        returnAmount = _swapInternalForSingleSwap(
            swapArgs.srcDistribution,
            amount,
            parts,
            lastNonZeroIndex,
            IERC20(swapArgs.srcSwap.srcToken),
            IERC20(swapArgs.srcSwap.dstToken)
        );
        require(returnAmount > 0, "Swap failed from dex");

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
        SwapArgsConnext calldata swapArgs,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        // break function to avoid stack too deep error
        returnAmount = _swapInternalWithParaSwap(
            IERC20(swapArgs.srcSwap.srcToken),
            IERC20(swapArgs.srcSwap.dstToken),
            amount,
            swapArgs.srcParaswapData
        );
    }

    function _emitCrossChainSwapRequest(
        SwapArgsConnext calldata swapArgs,
        bytes32 transferId,
        uint256 returnAmount,
        address sender,
        DataTypes.SwapStatus status
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            swapArgs.id,
            transferId,
            swapArgs.bridge,
            sender,
            swapArgs.srcSwap.srcToken,
            swapArgs.srcSwap.dstToken,
            swapArgs.dstSwap.dstToken,
            swapArgs.amount,
            returnAmount,
            swapArgs.estimatedDstTokenAmount,
            status
        );
    }

    function _emitCrossChainTransferRequest(
        TransferArgsConnext calldata transferArgs,
        bytes32 transferId,
        uint256 returnAmount,
        address sender,
        DataTypes.SwapStatus status
    )
        internal
    {
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
            transferArgs.bridgeDstAmount,
            status
        );
    }
}
