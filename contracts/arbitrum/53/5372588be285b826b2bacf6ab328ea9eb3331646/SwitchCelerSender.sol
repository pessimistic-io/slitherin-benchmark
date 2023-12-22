// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./Switch.sol";
import "./MessageSenderLib.sol";
import "./MsgDataTypes.sol";
import "./IMessageBus.sol";
import "./DataTypes.sol";
import { IPriceTracker } from "./IPriceTracker.sol";
import { ICBridge } from "./ICBridge.sol";

contract SwitchCelerSender is Switch {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;
    address public celerMessageBus;
    address public cBridge;
    address public priceTracker;
    address public nativeWrap;
    uint256 executorFee;
    uint256 claimableExecutionFee;

    struct CelerSwapRequest {
        bytes32 id;
        bytes32 bridge;
        address srcToken;
        address bridgeToken;
        address dstToken;
        address recipient;
        uint256 srcAmount;
        uint256 bridgeDstAmount;
        uint256 estimatedDstAmount;
        uint256 minDstAmount;
        uint256[] dstDistribution;
        bytes dstParaswapData;
        DataTypes.ParaswapUsageStatus paraswapUsageStatus;
    }

    struct TransferArgsCeler {
        address fromToken;
        address destToken;
        address recipient;
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 bridgeDstAmount;
        uint64 dstChainId;
        uint64 nonce;
        uint32 bridgeSlippage;
        bytes32 id;
        bytes32 bridge;
    }

    struct SwapArgsCeler {
        DataTypes.SwapInfo srcSwap;
        DataTypes.SwapInfo dstSwap;
        address recipient;
        address callTo; // The address of the destination app contract.
        address partner;
        uint256 partnerFeeRate;
        uint256 amount;
        uint256 expectedReturn; // expected bridge token amount on sending chain
        uint256 minSrcReturn; // min return from swap on src chain
        uint256 bridgeDstAmount; // estimated token amount of bridgeToken
        uint256 estimatedDstTokenAmount; // estimated dest token amount on receiving chain
        uint256 minDstAmount; // min dest token amount, will revert on dest chain if the amount is less than this
        uint256[] srcDistribution;
        uint256[] dstDistribution;
        uint64 dstChainId;
        uint64 nonce;
        uint32 bridgeSlippage;
        bytes32 id;
        bytes32 bridge;
        bytes srcParaswapData;
        bytes dstParaswapData;
        MsgDataTypes.BridgeSendType bridgeTransferType;
        DataTypes.ParaswapUsageStatus paraswapUsageStatus;
    }

    event ExecutorFeeClaimed(uint256 amount, address receiver);
    event CelerMessageBusSet(address celerMessageBus);
    event CBridgeSet(address cBridge);
    event PriceTrackerSet(address priceTracker);
    event ExecutorFeeSet(uint256 executorFee);
    event NativeWrapSet(address wrapAddress);

    constructor(
        address _weth,
        address _otherToken,
        uint256[] memory _pathCountAndSplit,
        address[] memory _factories,
        address[] memory _switchViewAndEventAddresses,
        address _celerMessageBus,
        address _cBridge,
        address _paraswapProxy,
        address _augustusSwapper,
        address _priceTracker,
        address _feeCollector
    ) Switch(_weth, _otherToken, _pathCountAndSplit[0], _pathCountAndSplit[1], _factories, _switchViewAndEventAddresses[0], _switchViewAndEventAddresses[1], _paraswapProxy, _augustusSwapper, _feeCollector)
        public
    {
        celerMessageBus = _celerMessageBus;
        cBridge = _cBridge;
        priceTracker = _priceTracker;
        nativeWrap = _weth;
    }

    modifier onlyMessageBus() {
        require(msg.sender == celerMessageBus, "caller is not message bus");
        _;
    }

    function setCelerMessageBus(address _celerMessageBus) external onlyOwner {
        celerMessageBus = _celerMessageBus;
        emit CelerMessageBusSet(celerMessageBus);
    }

    function cBridgeSet(address _cBridge) external onlyOwner {
        cBridge = _cBridge;
        emit CelerMessageBusSet(cBridge);
    }

    function setPriceTracker(address _priceTracker) external onlyOwner {
        priceTracker = _priceTracker;
        emit PriceTrackerSet(priceTracker);
    }

    function setExecutorFee(uint256 _executorFee) external onlyOwner {
        require(_executorFee > 0, "price cannot be 0");
        executorFee = _executorFee;
        emit ExecutorFeeSet(_executorFee);
    }

    function setNativeWrap(address _wrapAddress) external onlyOwner {
        nativeWrap = _wrapAddress;
        emit NativeWrapSet(nativeWrap);
    }

    function claimExecutorFee(address feeReceiver) external onlyOwner {
        payable(feeReceiver).transfer(claimableExecutionFee);
        emit ExecutorFeeClaimed(claimableExecutionFee, feeReceiver);
        claimableExecutionFee = 0;
    }

    function getAdjustedExecutorFee(uint256 dstChainId) public view returns(uint256) {
        return IPriceTracker(priceTracker).getPrice(block.chainid, dstChainId) * executorFee / 1e18;
    }

    function getSgnFeeByMessage(bytes memory message) public view returns(uint256) {
        return IMessageBus(celerMessageBus).calcFee(message);
    }

    function getSgnFee(
        CelerSwapRequest calldata request
    )
        external
        view
        returns (uint256 sgnFee)
    {

        bytes memory message = abi.encode(
            CelerSwapRequest({
                id: request.id,
                bridge: request.bridge,
                srcToken: request.srcToken,
                bridgeToken: request.bridgeToken,
                dstToken: request.dstToken,
                recipient: request.recipient,
                srcAmount: request.srcAmount,
                dstDistribution: request.dstDistribution,
                bridgeDstAmount: request.bridgeDstAmount,
                estimatedDstAmount: request.estimatedDstAmount,
                minDstAmount: request.minDstAmount,
                paraswapUsageStatus: request.paraswapUsageStatus,
                dstParaswapData: request.dstParaswapData
            })
        );

        sgnFee = IMessageBus(celerMessageBus).calcFee(message);
    }

    function transferByCeler(
        TransferArgsCeler calldata transferArgs
    )
        external
        payable
        nonReentrant
    {
        require(transferArgs.amount > 0, "The amount must be greater than zero");
        require(block.chainid != transferArgs.dstChainId, "Cannot bridge to same network");

        IERC20(transferArgs.fromToken).universalTransferFrom(msg.sender, address(this), transferArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(IERC20(transferArgs.fromToken), transferArgs.amount, transferArgs.partner, transferArgs.partnerFeeRate);

        bool isNative = IERC20(transferArgs.fromToken).isETH();
        if (isNative) {
            ICBridge(cBridge).sendNative{ value: amountAfterFee }(
                transferArgs.recipient,
                amountAfterFee,
                transferArgs.dstChainId,
                transferArgs.nonce,
                transferArgs.bridgeSlippage
            );
        } else {
            // Give cbridge approval
            IERC20(transferArgs.fromToken).safeApprove(cBridge, 0);
            IERC20(transferArgs.fromToken).safeApprove(cBridge, amountAfterFee);

            ICBridge(cBridge).send(
                transferArgs.recipient,
                transferArgs.fromToken,
                amountAfterFee,
                transferArgs.dstChainId,
                transferArgs.nonce,
                transferArgs.bridgeSlippage
            );
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(
                address(this),
                transferArgs.recipient,
                transferArgs.fromToken,
                amountAfterFee,
                transferArgs.dstChainId,
                transferArgs.nonce,
                uint64(block.chainid)
            )
        );
        _emitCrossChainTransferRequest(transferArgs, transferId, amountAfterFee, msg.sender, DataTypes.SwapStatus.Succeeded);
    }

    function swapByCeler(
        SwapArgsCeler calldata swapArgs
    )
        external
        payable
        nonReentrant
        returns (bytes32 transferId)
    {
        require(swapArgs.expectedReturn >= swapArgs.minSrcReturn, "return amount was not enough");
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
            bridgeTokenIsNative = true;
        }
        if (swapArgs.srcSwap.srcToken == nativeWrap && IERC20(swapArgs.srcSwap.dstToken).isETH()) {
            bridgeTokenIsNative = true;
        }


        bytes memory message = abi.encode(
            CelerSwapRequest({
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
                estimatedDstAmount: swapArgs.estimatedDstTokenAmount,
                minDstAmount: swapArgs.minDstAmount
            })
        );

        uint256 adjustedExecutionFee = getAdjustedExecutorFee(swapArgs.dstChainId);
        uint256 sgnFee = getSgnFeeByMessage(message);
        if (IERC20(swapArgs.srcSwap.srcToken).isETH()) {
            require(msg.value >= swapArgs.amount + sgnFee + adjustedExecutionFee, 'native token is not enough');
        } else {
            require(msg.value >= sgnFee + adjustedExecutionFee, 'native token is not enough');
        }

        claimableExecutionFee += adjustedExecutionFee;

        if (swapArgs.srcSwap.srcToken == swapArgs.srcSwap.dstToken || bridgeTokenIsNative) {
            returnAmount = amountAfterFee;
        } else {
            if ((swapArgs.paraswapUsageStatus == DataTypes.ParaswapUsageStatus.OnSrcChain) ||
                (swapArgs.paraswapUsageStatus == DataTypes.ParaswapUsageStatus.Both))
            {
                returnAmount = _swapFromParaswap(swapArgs, amountAfterFee);
            } else {
                (returnAmount, ) = _swapBeforeCeler(swapArgs, amountAfterFee);
            }
            if (IERC20(swapArgs.srcSwap.dstToken).isETH()) {
                weth.deposit{value: returnAmount}();
                weth.approve(cBridge, returnAmount);
            }
        }

        require(returnAmount >= swapArgs.minSrcReturn, 'The amount too small');

        //MessageSenderLib is your swiss army knife of sending messages
        transferId = MessageSenderLib.sendMessageWithTransfer(
            swapArgs.callTo,
            bridgeTokenIsNative ? nativeWrap : swapArgs.srcSwap.dstToken,
            returnAmount,
            swapArgs.dstChainId,
            swapArgs.nonce,
            swapArgs.bridgeSlippage,
            message,
            swapArgs.bridgeTransferType,
            celerMessageBus,
            sgnFee
        );

        _emitCrossChainSwapRequest(swapArgs, transferId, returnAmount, msg.sender, DataTypes.SwapStatus.Succeeded);
    }

    function _swapFromParaswap(
        SwapArgsCeler calldata swapArgs,
        uint256 amount
    )
        private
        returns (uint256 returnAmount)
    {
        // break function to avoid stack too deep error
        returnAmount = _swapInternalWithParaSwap(IERC20(swapArgs.srcSwap.srcToken), IERC20(swapArgs.srcSwap.dstToken), amount, swapArgs.srcParaswapData);
    }

    function _swapBeforeCeler(SwapArgsCeler calldata transferArgs, uint256 amount) private returns (uint256 returnAmount, uint256 parts) {
        parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint i = 0; i < transferArgs.srcDistribution.length; i++) {
            if (transferArgs.srcDistribution[i] > 0) {
                parts += transferArgs.srcDistribution[i];
                lastNonZeroIndex = i;
            }
        }

        require(parts > 0, "invalid distribution param");

        // break function to avoid stack too deep error
        returnAmount = _swapInternalForSingleSwap(transferArgs.srcDistribution, amount, parts, lastNonZeroIndex, IERC20(transferArgs.srcSwap.srcToken), IERC20(transferArgs.srcSwap.dstToken));
        require(returnAmount > 0, "Swap failed from dex");

        switchEvent.emitSwapped(msg.sender, address(this), IERC20(transferArgs.srcSwap.srcToken), IERC20(transferArgs.srcSwap.dstToken), amount, returnAmount, 0);
    }

    function _emitCrossChainSwapRequest(SwapArgsCeler calldata transferArgs, bytes32 transferId, uint256 returnAmount, address sender, DataTypes.SwapStatus status) internal {
        switchEvent.emitCrosschainSwapRequest(
            transferArgs.id,
            transferId,
            transferArgs.bridge,
            sender,
            transferArgs.srcSwap.srcToken,
            transferArgs.srcSwap.dstToken,
            transferArgs.dstSwap.dstToken,
            transferArgs.amount,
            returnAmount,
            transferArgs.estimatedDstTokenAmount,
            status
        );
    }

    function _emitCrossChainTransferRequest(TransferArgsCeler calldata transferArgs, bytes32 transferId, uint256 returnAmount, address sender, DataTypes.SwapStatus status) internal {
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
