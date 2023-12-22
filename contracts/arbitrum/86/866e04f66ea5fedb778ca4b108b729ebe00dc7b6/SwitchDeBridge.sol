// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./DataTypes.sol";
import "./Switch.sol";
import "./ReentrancyGuard.sol";
import "./IDeBridgeGate.sol";

contract SwitchDeBridge is Switch {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;
    address public deBridgeGate;

    struct SwapArgsDeBridge {
        DataTypes.SwapInfo srcSwap;
        DataTypes.SwapInfo dstSwap;
        address payable recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 expectedReturn;
        uint256 minReturn;
        uint256 nativeFee;
        uint256 estimatedDstTokenAmount;
        uint256 dstChainId;
        bool useAssetFee;
        bool useParaswap;
        uint32 referralCode;
        bytes32 id;
        bytes32 bridge;
        bytes permit;
        bytes autoParams;
        bytes srcParaswapData;
        uint256[] srcDistribution;
    }

    struct TransferArgsDeBridge {
        address fromToken;
        address destToken;
        address payable recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 nativeFee;
        uint256 estimatedDstTokenAmount;
        uint256 dstChainId;
        bool useAssetFee;
        uint32 referralCode;
        bytes32 id;
        bytes32 bridge;
        bytes permit;
        bytes autoParams;
    }

    event DeBridgeGateSet(address deBridgeGate);

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
        address _deBridgeGate
    ) Switch(_weth, _otherToken, _pathCount, _pathSplit, _factories, _switchViewAndEventAddresses[0], _switchViewAndEventAddresses[1], _paraswapProxy, _augustusSwapper, _feeCollector)
        public
    {
        deBridgeGate = _deBridgeGate;
    }

    function setDeBridgeGate(address _deBridgeGate) external onlyOwner {
        deBridgeGate = _deBridgeGate;
        emit DeBridgeGateSet(_deBridgeGate);
    }

    function transferByDeBridge(
        TransferArgsDeBridge calldata transferArgs
    )
        external
        payable
        nonReentrant
    {
        require(transferArgs.amount > 0, "The amount must be greater than zero");
        require(block.chainid != transferArgs.dstChainId, "Cannot bridge to same network");

        address fromToken = transferArgs.fromToken;
        IERC20(fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(IERC20(fromToken), transferArgs.amount, transferArgs.partner, transferArgs.partnerFeeRate);
        bool isNative = IERC20(fromToken).isETH();
        uint256 nativeAssetAmount = 0;

        if (isNative) {
            nativeAssetAmount = msg.value;
        } else {
            nativeAssetAmount = transferArgs.nativeFee;
            IERC20(fromToken).universalApprove(deBridgeGate, amountAfterFee);
        }

        IDeBridgeGate(deBridgeGate).send{ value: nativeAssetAmount }(
            fromToken,
            amountAfterFee,
            transferArgs.dstChainId,
            abi.encodePacked(transferArgs.recipient),
            transferArgs.permit,
            transferArgs.useAssetFee,
            transferArgs.referralCode,
            transferArgs.autoParams
        );

        _emitCrossChainTransferRequest(
            transferArgs,
            bytes32(0),
            amountAfterFee,
            msg.sender,
            DataTypes.SwapStatus.Succeeded
        );
    }

    function swapByDeBridge(
        SwapArgsDeBridge calldata swapArgs
    )
        external
        payable
        nonReentrant
    {
        require(swapArgs.expectedReturn >= swapArgs.minReturn, "expectedReturn must be equal or larger than minReturn");

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

        IERC20(swapArgs.srcSwap.dstToken).universalApprove(deBridgeGate, returnAmount);
        IDeBridgeGate(deBridgeGate).send{ value: swapArgs.nativeFee }(
            swapArgs.srcSwap.dstToken,
            returnAmount,
            swapArgs.dstChainId,
            abi.encodePacked(swapArgs.recipient),
            swapArgs.permit,
            swapArgs.useAssetFee,
            swapArgs.referralCode,
            swapArgs.autoParams
        );

        _emitCrossChainSwapRequest(swapArgs, returnAmount, msg.sender);

    }

    function _swapFromAggregator(
        SwapArgsDeBridge calldata swapArgs,
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
        SwapArgsDeBridge calldata transferArgs,
        bytes calldata callData,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        // break function to avoid stack too deep error
        returnAmount = _swapInternalWithParaSwap(IERC20(transferArgs.srcSwap.srcToken), IERC20(transferArgs.srcSwap.dstToken), amount, callData);
    }

    function _emitCrossChainTransferRequest(
        TransferArgsDeBridge calldata transferArgs,
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
            transferArgs.estimatedDstTokenAmount,
            status
        );
    }

    function _emitCrossChainSwapRequest(
        SwapArgsDeBridge calldata swapArgs,
        uint256 returnAmount,
        address sender
    )
        internal
    {
        switchEvent.emitCrosschainSwapRequest(
            swapArgs.id,
            bytes32(0),
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

