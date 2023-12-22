// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./IOrderBook.sol";
import "./ILighterV2TransferCallback.sol";
import "./IFactory.sol";
import "./PeripheryErrors.sol";
import "./SafeTransfer.sol";
import "./Quoter.sol";
import "./IWETH9.sol";
import "./IRouter.sol";

/// @title Router
/// @notice Router for interacting with order books to perform order operations, swaps and views
contract Router is IRouter, ILighterV2TransferCallback {
    using SafeTransferLib for IERC20Minimal;
    using QuoterLib for IFactory;

    /// @notice The address of the factory contract that manages order book deployments
    IFactory public immutable factory;

    /// @notice The address of the Wrapped Ether (WETH) contract
    IWETH9 public immutable weth9;

    /// @notice Struct to hold local variables for internal functions logic
    struct LocalVars {
        uint256 swapAmount0; // Amount of token0 to swap
        uint256 swapAmount1; // Amount of token1 to swap
        uint256 swappedInput; // Amount of input token swapped
        uint256 swappedOutput; // Amount of output token swapped
        uint256 exactInput; // Amount of the exact-input-token used in the swap
        address sender; // Address of the payer of the swap
        address recipient; // Address of the recipient
    }

    /// @dev Constructor to initialize the Router with factory and WETH contract addresses
    /// @param _factoryAddress The address of the factory contract.
    /// @param _wethAddress The address of the Wrapped Ether (WETH) contract
    constructor(address _factoryAddress, address _wethAddress) {
        factory = IFactory(_factoryAddress);
        weth9 = IWETH9(_wethAddress);
    }

    receive() external payable {
        revert PeripheryErrors.LighterV2Router_ReceiveNotSupported();
    }

    /// @inheritdoc IRouter
    function createLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint64[] memory amount0Base,
        uint64[] memory priceBase,
        bool[] memory isAsk,
        uint32[] memory hintId
    ) external override returns (uint32[] memory orderId) {
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        orderId = new uint32[](size);
        bytes memory callbackData = abi.encodePacked(orderBookId, msg.sender);
        for (uint8 i; i < size; ) {
            orderId[i] = orderBook.createOrder(
                amount0Base[i],
                priceBase[i],
                isAsk[i],
                msg.sender,
                hintId[i],
                IOrderBook.OrderType.LimitOrder,
                callbackData
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IRouter
    function createLimitOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk,
        uint32 hintId
    ) public override returns (uint32 orderId) {
        orderId = _getOrderBookFromId(orderBookId).createOrder(
            amount0Base,
            priceBase,
            isAsk,
            msg.sender,
            hintId,
            IOrderBook.OrderType.LimitOrder,
            abi.encodePacked(orderBookId, msg.sender)
        );
    }

    /// @inheritdoc IRouter
    function createFoKOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk
    ) public override returns (uint32 orderId) {
        orderId = _getOrderBookFromId(orderBookId).createOrder(
            amount0Base,
            priceBase,
            isAsk,
            msg.sender,
            0,
            IOrderBook.OrderType.FoKOrder,
            abi.encodePacked(orderBookId, msg.sender)
        );
    }

    /// @inheritdoc IRouter
    function createIoCOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk
    ) public override returns (uint32 orderId) {
        orderId = _getOrderBookFromId(orderBookId).createOrder(
            amount0Base,
            priceBase,
            isAsk,
            msg.sender,
            0,
            IOrderBook.OrderType.IoCOrder,
            abi.encodePacked(orderBookId, msg.sender)
        );
    }

    /// @inheritdoc IRouter
    function updateLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId,
        uint64[] memory newAmount0Base,
        uint64[] memory newPriceBase,
        uint32[] memory hintId
    ) external override returns (uint32[] memory newOrderId) {
        newOrderId = new uint32[](size);
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        bool isCanceled;
        bool isAsk;
        bytes memory callbackData = abi.encodePacked(orderBookId, msg.sender);
        for (uint256 i; i < size; ) {
            if (!orderBook.isOrderActive(orderId[i])) {
                newOrderId[i] = 0;
                unchecked {
                    ++i;
                }
                continue;
            }
            isAsk = orderBook.isAskOrder(orderId[i]);
            isCanceled = orderBook.cancelLimitOrder(orderId[i], msg.sender);

            // Should not happen since function checks if the order is active above
            if (!isCanceled) {
                newOrderId[i] = 0;
            } else {
                newOrderId[i] = orderBook.createOrder(
                    newAmount0Base[i],
                    newPriceBase[i],
                    isAsk,
                    msg.sender,
                    hintId[i],
                    IOrderBook.OrderType.LimitOrder,
                    callbackData
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IRouter
    function updateLimitOrder(
        uint8 orderBookId,
        uint32 orderId,
        uint64 newAmount0Base,
        uint64 newPriceBase,
        uint32 hintId
    ) public override returns (uint32 newOrderId) {
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        if (!orderBook.isOrderActive(orderId)) {
            newOrderId = 0;
        } else {
            bool isAsk = orderBook.isAskOrder(orderId);
            if (orderBook.cancelLimitOrder(orderId, msg.sender)) {
                newOrderId = orderBook.createOrder(
                    newAmount0Base,
                    newPriceBase,
                    isAsk,
                    msg.sender,
                    hintId,
                    IOrderBook.OrderType.LimitOrder,
                    abi.encodePacked(orderBookId, msg.sender)
                );
            } else {
                // Should not happen since function checks if the order is active above
                newOrderId = 0;
            }
        }
    }

    /// @inheritdoc IRouter
    function cancelLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId
    ) external override returns (bool[] memory isCanceled) {
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        isCanceled = new bool[](size);
        for (uint256 i; i < size; ) {
            isCanceled[i] = orderBook.cancelLimitOrder(orderId[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IRouter
    function cancelLimitOrder(uint8 orderBookId, uint32 orderId) public override returns (bool) {
        return _getOrderBookFromId(orderBookId).cancelLimitOrder(orderId, msg.sender);
    }

    /// @inheritdoc IRouter
    function swapExactInputSingle(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactInput,
        uint256 minOutput,
        address recipient,
        bool unwrap
    ) public payable override returns (uint256 swappedInput, uint256 swappedOutput) {
        uint256 swapAmount0;
        uint256 swapAmount1;
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);

        if (msg.value > 0 && msg.value < exactInput) {
            revert PeripheryErrors.LighterV2Router_NotEnoughNative();
        }

        bytes memory callbackData = abi.encodePacked(orderBookId, msg.sender);

        (swapAmount0, swapAmount1) = orderBook.swapExactSingle(
            isAsk,
            true,
            exactInput,
            minOutput,
            (unwrap) ? address(this) : recipient,
            callbackData
        );

        if (isAsk) {
            (swappedInput, swappedOutput) = (swapAmount0, swapAmount1);
        } else {
            (swappedInput, swappedOutput) = (swapAmount1, swapAmount0);
        }

        if (msg.value > 0) {
            _handleNativeRefund();
        }

        if (unwrap) {
            _unwrapWETH9AndTransfer(recipient, swappedOutput);
        }
    }

    /// @inheritdoc IRouter
    function swapExactOutputSingle(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactOutput,
        uint256 maxInput,
        address recipient,
        bool unwrap
    ) public payable returns (uint256 swappedInput, uint256 swappedOutput) {
        uint256 swapAmount0;
        uint256 swapAmount1;
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);

        if (msg.value > 0 && msg.value < maxInput) {
            revert PeripheryErrors.LighterV2Router_NotEnoughNative();
        }

        bytes memory callbackData = abi.encodePacked(orderBookId, msg.sender);

        (swapAmount0, swapAmount1) = orderBook.swapExactSingle(
            isAsk,
            false,
            exactOutput,
            maxInput,
            (unwrap) ? address(this) : recipient,
            callbackData
        );

        if (isAsk) {
            (swappedInput, swappedOutput) = (swapAmount0, swapAmount1);
        } else {
            (swappedInput, swappedOutput) = (swapAmount1, swapAmount0);
        }

        if (msg.value > 0) {
            _handleNativeRefund();
        }

        if (unwrap) {
            _unwrapWETH9AndTransfer(recipient, swappedOutput);
        }
    }

    /// @inheritdoc IRouter
    function swapExactInputMulti(
        MultiPathExactInputRequest memory multiPathExactInputRequest
    ) public payable returns (uint256 swappedInput, uint256 swappedOutput) {
        // In the case of a single order book, forward call to swapExactInputSingle
        if (multiPathExactInputRequest.swapRequests.length == 1) {
            return
                swapExactInputSingle(
                    multiPathExactInputRequest.swapRequests[0].orderBookId,
                    multiPathExactInputRequest.swapRequests[0].isAsk,
                    multiPathExactInputRequest.exactInput,
                    multiPathExactInputRequest.minOutput,
                    multiPathExactInputRequest.recipient,
                    multiPathExactInputRequest.unwrap
                );
        }
        factory.validateMultiPathSwap(multiPathExactInputRequest.swapRequests);
        return _executeSwapExactInputMulti(multiPathExactInputRequest);
    }

    /// @inheritdoc IRouter
    function swapExactOutputMulti(
        MultiPathExactOutputRequest memory multiPathExactOutputRequest
    ) public payable returns (uint256 swappedInput, uint256 swappedOutput) {
        // In the case of a single order book, forward call to swapExactOutputSingle
        if (multiPathExactOutputRequest.swapRequests.length == 1) {
            return
                swapExactOutputSingle(
                    multiPathExactOutputRequest.swapRequests[0].orderBookId,
                    multiPathExactOutputRequest.swapRequests[0].isAsk,
                    multiPathExactOutputRequest.exactOutput,
                    multiPathExactOutputRequest.maxInput,
                    multiPathExactOutputRequest.recipient,
                    multiPathExactOutputRequest.unwrap
                );
        }
        factory.validateMultiPathSwap(multiPathExactOutputRequest.swapRequests);

        (uint256 quotedInput, uint256 quotedOutput) = factory.getQuoteForExactOutputMulti(
            multiPathExactOutputRequest.swapRequests,
            multiPathExactOutputRequest.exactOutput
        );

        // Verify that the quotedInput is smaller than or equal to user provided maxInput
        if (quotedInput > multiPathExactOutputRequest.maxInput) {
            revert PeripheryErrors.LighterV2Router_SwapExactOutputMultiTooMuchRequested();
        }

        return
            _executeSwapExactInputMulti(
                MultiPathExactInputRequest({
                    swapRequests: multiPathExactOutputRequest.swapRequests,
                    exactInput: quotedInput,
                    minOutput: quotedOutput,
                    recipient: multiPathExactOutputRequest.recipient,
                    unwrap: multiPathExactOutputRequest.unwrap
                })
            );
    }

    /// @inheritdoc ILighterV2TransferCallback
    function lighterV2TransferCallback(
        uint256 debitTokenAmount,
        IERC20Minimal debitToken,
        bytes memory _data
    ) external override {
        uint8 orderBookId;
        address payer;

        // Unpack data
        assembly {
            orderBookId := mload(add(_data, 1))
            payer := mload(add(_data, 21))
        }

        // Check if sender is a valid order book
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        if (msg.sender != address(orderBook)) {
            revert PeripheryErrors.LighterV2Router_TransferCallbackCallerIsNotOrderBook();
        }

        if (address(debitToken) == address(weth9) && address(this).balance >= debitTokenAmount) {
            // Pay with WETH9
            IWETH9(weth9).depositTo{value: debitTokenAmount}(msg.sender);
        } else if (payer == address(this)) {
            // Pay with tokens already in the contract (for the exact input multi path case)
            debitToken.safeTransfer(msg.sender, debitTokenAmount);
        } else {
            // Pull payment
            debitToken.safeTransferFrom(payer, msg.sender, debitTokenAmount);
        }
    }

    /// @notice This function is called when no other router function is called
    /// @dev The data should be passed in msg.data
    /// Fallback function is to be used for calldata optimization.
    /// The first byte of msg.data should be the function selector:
    /// 1 = createLimitOrder
    /// 2 = updateLimitOrder
    /// 3 = cancelLimitOrder
    /// 4 + 0 = createIoCOrder -- isAsk=false
    ///   + 1 = createIoCOrder -- isAsk=true
    /// 6 + 0 = createFoKOrder -- isAsk=false
    ///   + 1 = createFoKOrder -- isAsk=true
    /// 8 + 0 = swapExactInputSingle -- unwrap=false, recipientIsMsgSender=false
    ///   + 1 = swapExactInputSingle -- unwrap=true, recipientIsMsgSender=false
    ///   + 2 = swapExactInputSingle -- unwrap=false, recipientIsMsgSender=true
    ///   + 3 = swapExactInputSingle -- unwrap=true, recipientIsMsgSender=true
    /// 12 + 0 = swapExactOutputSingle -- unwrap=false, recipientIsMsgSender=false
    ///    + 1 = swapExactOutputSingle -- unwrap=true, recipientIsMsgSender=false
    ///    + 2 = swapExactOutputSingle -- unwrap=false, recipientIsMsgSender=true
    ///    + 3 = swapExactOutputSingle -- unwrap=true, recipientIsMsgSender=true
    /// 16 + 0 = swapExactInputMulti -- unwrap=false, recipientIsMsgSender=false
    ///    + 1 = swapExactInputMulti -- unwrap=true, recipientIsMsgSender=false
    ///    + 2 = swapExactInputMulti -- unwrap=false, recipientIsMsgSender=true
    ///    + 3 = swapExactInputMulti -- unwrap=true, recipientIsMsgSender=true
    /// 20 + 0 = swapExactOutputMulti -- unwrap=false, recipientIsMsgSender=false
    ///    + 1 = swapExactOutputMulti -- unwrap=true, recipientIsMsgSender=false
    ///    + 2 = swapExactOutputMulti -- unwrap=false, recipientIsMsgSender=true
    ///    + 3 = swapExactOutputMulti -- unwrap=true, recipientIsMsgSender=true
    /// The next byte should be the id of the order book
    /// Remaining bytes should be order or swap details
    fallback() external payable {
        uint256 _func;
        uint256 dataLength = msg.data.length;

        uint256 currentByte = 1;
        _func = _parseCallData(0, dataLength, 1);

        uint256 value;
        uint8 parsed;

        // Group order-related operations together
        if (_func < 8) {
            uint8 orderBookId = uint8(_parseCallData(1, dataLength, 1));
            IOrderBook orderBook = _getOrderBookFromId(orderBookId);
            currentByte = 2;

            uint64 amount0Base;
            uint64 priceBase;
            uint32 hintId;
            uint256 isAsk;
            uint32 orderId;

            // Create limit order
            if (_func == 1) {
                // Parse all isAsk bits, at once, in a compressed form
                (isAsk, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                currentByte += parsed;

                bytes memory callbackData = abi.encodePacked(orderBookId, msg.sender);

                while (currentByte < dataLength) {
                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    amount0Base = uint64(value);
                    currentByte += parsed;

                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    priceBase = uint64(value);
                    currentByte += parsed;

                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    if(value > 0xFFFFFFFF) {
                        revert PeripheryErrors.LighterV2ParseCallData_InvalidPaddedNumber();
                    }
                    hintId = uint32(value);
                    currentByte += parsed;

                    if (currentByte > dataLength) {
                        revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
                    }

                    orderBook.createOrder(
                        amount0Base,
                        priceBase,
                        isAsk & 1 > 0,
                        msg.sender,
                        hintId,
                        IOrderBook.OrderType.LimitOrder,
                        callbackData
                    );

                    // Consume 1 isAsk bit
                    isAsk >>= 1;
                }
            }
            // Update limit order
            else if (_func == 2) {
                while (currentByte < dataLength) {
                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    if(value > 0xFFFFFFFF) {
                        revert PeripheryErrors.LighterV2ParseCallData_InvalidPaddedNumber();
                    }
                    orderId = uint32(value);
                    currentByte += parsed;

                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    amount0Base = uint64(value);
                    currentByte += parsed;

                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    priceBase = uint64(value);
                    currentByte += parsed;

                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    if(value > 0xFFFFFFFF) {
                        revert PeripheryErrors.LighterV2ParseCallData_InvalidPaddedNumber();
                    }
                    hintId = uint32(value);
                    currentByte += parsed;

                    if (currentByte > dataLength) {
                        revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
                    }

                    updateLimitOrder(orderBookId, orderId, amount0Base, priceBase, hintId);
                }
            }
            // Cancel limit order
            else if (_func == 3) {
                while (currentByte < dataLength) {
                    (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                    if(value > 0xFFFFFFFF) {
                        revert PeripheryErrors.LighterV2ParseCallData_InvalidPaddedNumber();
                    }
                    orderId = uint32(value);
                    currentByte += parsed;

                    if (currentByte > dataLength) {
                        revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
                    }

                    orderBook.cancelLimitOrder(orderId, msg.sender);
                }
            }
            // Create IoC order
            else if (_func == 4 || _func == 5) {
                bool isAskByte = (_func == 5);

                (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                amount0Base = uint64(value);
                currentByte += parsed;

                (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                priceBase = uint64(value);
                currentByte += parsed;

                if (currentByte > dataLength) {
                    revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
                }

                createIoCOrder(orderBookId, amount0Base, priceBase, isAskByte);

                return;
            }
            // Create FoK order
            else if (_func == 6 || _func == 7) {
                bool isAskByte = (_func == 7);

                (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                amount0Base = uint64(value);
                currentByte += parsed;

                (value, parsed) = _parseSizePaddedNumberFromCallData(currentByte, dataLength);
                priceBase = uint64(value);
                currentByte += parsed;

                if (currentByte > dataLength) {
                    revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
                }

                createFoKOrder(orderBookId, amount0Base, priceBase, isAskByte);

                return;
            }
        }
        /// swapExactInputSingle with mantissa representation
        else if (_func >= 8 && _func < 8 + 4) {
            // Parse compressed isAsk & orderBookId
            (bool isAsk, uint8 orderBookId) = _parseCompressedOBFromCallData(1, dataLength);
            currentByte = 2;

            uint256 exactInput;
            uint256 minOutput;

            (exactInput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            (minOutput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            uint8 recipientIsMsgSender = uint8((_func - 8) & 2);
            address recipient = (recipientIsMsgSender > 0)
                ? msg.sender
                : address(uint160(_parseCallData(currentByte, dataLength, 20)));
            if (recipientIsMsgSender == 0) currentByte += 20;
            bool unwrap = ((_func - 8) & 1) > 0;

            swapExactInputSingle(orderBookId, isAsk, exactInput, minOutput, recipient, unwrap);
            return;
        }
        /// swapExactOutputSingle with mantissa representation
        else if (_func >= 12 && _func < 12 + 4) {
            // Parse compressed isAsk & orderBookId
            (bool isAsk, uint8 orderBookId) = _parseCompressedOBFromCallData(1, dataLength);
            currentByte = 2;

            uint256 exactOutput;
            uint256 maxInput;

            (exactOutput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            (maxInput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            uint8 recipientIsMsgSender = uint8((_func - 12) & 2);
            address recipient = (recipientIsMsgSender > 0)
                ? msg.sender
                : address(uint160(_parseCallData(currentByte, dataLength, 20)));
            if (recipientIsMsgSender == 0) currentByte += 20;
            bool unwrap = ((_func - 12) & 1) > 0;

            swapExactOutputSingle(orderBookId, isAsk, exactOutput, maxInput, recipient, unwrap);
            return;
        }
        /// swapExactInputMulti with mantissa representation
        else if (_func >= 16 && _func < 16 + 4) {
            currentByte = 1;

            MultiPathExactInputRequest memory request;

            (request.exactInput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            (request.minOutput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            uint8 recipientIsMsgSender = uint8((_func - 16) & 2);
            if (recipientIsMsgSender > 0) {
                request.recipient = msg.sender;
            } else {
                request.recipient = address(uint160(_parseCallData(currentByte, dataLength, 20)));
                currentByte += 20;
            }
            request.unwrap = ((_func - 16) & 1) > 0;

            // Remaining callData is request.swapRequests
            uint256 remaining = dataLength - currentByte;
            request.swapRequests = new SwapRequest[](remaining);
            for (uint256 index = 0; index < remaining; ) {
                (
                    request.swapRequests[index].isAsk,
                    request.swapRequests[index].orderBookId
                ) = _parseCompressedOBFromCallData(currentByte, dataLength);
                currentByte += 1;
                unchecked {
                    ++index;
                }
            }

            swapExactInputMulti(request);
            return;
        }
        /// swapExactOutputMulti with mantissa representation
        else if (_func >= 20 && _func < 20 + 4) {
            currentByte = 1;

            MultiPathExactOutputRequest memory request;

            (request.exactOutput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            (request.maxInput, parsed) = _parseNumberMantissaFromCallData(currentByte, dataLength);
            currentByte += parsed;

            uint8 recipientIsMsgSender = uint8((_func - 20) & 2);
            if (recipientIsMsgSender > 0) {
                request.recipient = msg.sender;
            } else {
                request.recipient = address(uint160(_parseCallData(currentByte, dataLength, 20)));
                currentByte += 20;
            }
            request.unwrap = ((_func - 20) & 1) > 0;

            // remaining CallData is request.swapRequests
            uint256 remaining = dataLength - currentByte;
            request.swapRequests = new SwapRequest[](remaining);
            for (uint256 index = 0; index < remaining; ) {
                (
                    request.swapRequests[index].isAsk,
                    request.swapRequests[index].orderBookId
                ) = _parseCompressedOBFromCallData(currentByte, dataLength);
                currentByte += 1;
                unchecked {
                    ++index;
                }
            }

            swapExactOutputMulti(request);
            return;
        } 
        /// Invalid function selector
        else {
            revert PeripheryErrors.LighterV2ParseCallData_InvalidFunctionSelector();
        }
    }

    /// @dev Execute the MultiPathExactInputRequest after it has been validated.
    /// This exists as a separate function because it's also called by swapExactOutputMulti
    function _executeSwapExactInputMulti(
        MultiPathExactInputRequest memory multiPathExactInputRequest
    ) internal returns (uint256 swappedInput, uint256 swappedOutput) {
        if (msg.value > 0 && msg.value < multiPathExactInputRequest.exactInput) {
            revert PeripheryErrors.LighterV2Router_NotEnoughNative();
        }

        LocalVars memory localVars;
        localVars.exactInput = multiPathExactInputRequest.exactInput;
        uint256 requestsLength = multiPathExactInputRequest.swapRequests.length;

        for (uint index; index < requestsLength; ) {
            SwapRequest memory swapRequest = multiPathExactInputRequest.swapRequests[index];
            IOrderBook orderBook = _getOrderBookFromId(swapRequest.orderBookId);

            // If this is not the last request or if unwrap is set to true then the recipient will be the router.
            // Otherwise the recipient will be the recipient provided by the multi-swap initiator
            localVars.recipient = (requestsLength != index + 1)
                ? address(this)
                : ((multiPathExactInputRequest.unwrap) ? address(this) : multiPathExactInputRequest.recipient);

            // If this is the first request, sender will pay, for the rest of the requests, router will pay
            localVars.sender = (index == 0) ? msg.sender : address(this);

            (localVars.swapAmount0, localVars.swapAmount1) = orderBook.swapExactSingle(
                swapRequest.isAsk,
                true,
                localVars.exactInput,
                (index + 1 == requestsLength) ? multiPathExactInputRequest.minOutput : 0,
                localVars.recipient,
                abi.encodePacked(swapRequest.orderBookId, localVars.sender)
            );

            // If router is the sender and swapped input amount is less than the token amount in the router, refund the difference
            if (localVars.sender == address(this)) {
                uint256 refundAmount = swapRequest.isAsk
                    ? localVars.exactInput - localVars.swapAmount0
                    : localVars.exactInput - localVars.swapAmount1;

                // Send refund tokens from router to recipient of request
                if (refundAmount > 0) {
                    IERC20Minimal refundToken = swapRequest.isAsk ? orderBook.token0() : orderBook.token1();
                    refundToken.safeTransfer(multiPathExactInputRequest.recipient, refundAmount);
                }
            }

            if (index == 0) {
                localVars.swappedInput = swapRequest.isAsk ? localVars.swapAmount0 : localVars.swapAmount1;
            }
            localVars.exactInput = swapRequest.isAsk ? localVars.swapAmount1 : localVars.swapAmount0;

            unchecked {
                ++index;
            }
        }

        localVars.swappedOutput = localVars.exactInput;

        if (msg.value > 0) {
            _handleNativeRefund();
        }

        if (multiPathExactInputRequest.unwrap) {
            _unwrapWETH9AndTransfer(multiPathExactInputRequest.recipient, localVars.swappedOutput);
        }

        return (localVars.swappedInput, localVars.swappedOutput);
    }

    /// @dev Transfer all ETH to caller
    /// Does not care about the swap results since Router contract should not store any funds
    /// before or after transactions
    function _handleNativeRefund() internal {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(msg.sender).call{value: balance}("");
            if(!success) {
                revert PeripheryErrors.LighterV2Router_NativeRefundFailed();
            }
        }
    }

    /// @dev Unwrap the WETH9 tokens and transfer the native to recipient
    /// @param recipient Address of recipient
    /// @param amount Amount of WETH9 to be unwrapped to native
    function _unwrapWETH9AndTransfer(address recipient, uint256 amount) internal {
        uint256 balanceWETH9 = weth9.balanceOf(address(this));
        if (balanceWETH9 < amount) {
            revert PeripheryErrors.LighterV2Router_InsufficientWETH9();
        }
        if (amount > 0) {
            weth9.withdrawTo(recipient, amount);
        }
    }

    /// @dev Get the uint value from msg.data starting from a specific byte
    /// @param startByte Index of startByte of calldata
    /// @param msgDataLength Length of the data bytes in msg
    /// @param length The number of bytes to read
    /// @return val Parsed uint256 value from calldata
    function _parseCallData(uint256 startByte, uint256 msgDataLength, uint256 length) internal pure returns (uint256) {
        uint256 val;

        if (length > 32) {
            revert PeripheryErrors.LighterV2ParseCallData_ByteSizeLimit32();
        }

        if (length + startByte > msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }

        assembly {
            val := calldataload(startByte)
        }

        val = val >> (256 - length * 8);

        return val;
    }

    /// @dev Parse a number using the exponent and mantissa values from msg.data, starting from the given startByte
    /// The data for mantissa and exponent has the following format:
    /// 2 bits for type, 6 bits for exponent and 3, 5 or 7 bytes for mantissa part of the value depending on the type
    /// @param startByte Index of startByte of calldata
    /// @param msgDataLength Length of the data bytes in msg
    /// @return value Parsed uint256 number
    /// @return parsedBytes The number of bytes read to parse `value`
    function _parseNumberMantissaFromCallData(
        uint256 startByte,
        uint256 msgDataLength
    ) internal pure returns (uint256 value, uint8 parsedBytes) {
        if (startByte >= msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }
        uint256 val;
        assembly {
            val := calldataload(startByte)
        }

        uint8 mantissaType = uint8(val >> (256 - 2));
        uint256 exponent = (val >> (256 - 8)) - (mantissaType << 6);

        if (mantissaType > 2 || exponent > 60) {
            revert PeripheryErrors.LighterV2ParseCallData_InvalidMantissa();
        }

        // For mantissaType = 0, needs to read 3 bytes
        // For mantissaType = 1, needs to read 5 bytes
        // For mantissaType = 2, needs to read 7 bytes
        if (startByte + 3 + 2 * mantissaType >= msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }

        val = (val << 8); // Get rid of the type and exponent

        // For mantissaType = 0, needs to read most significant 24 bits (3 bytes), val >> 232
        // For mantissaType = 1, needs to read most significant 40 bits (5 bytes), val >> 216
        // For mantissaType = 2, needs to read most significant 56 bits (7 bytes), val >> 200
        // Largest exponent can be 60 and maximum value van be is 2^56-1,
        // since 10^60 * (2^56-1) < 2^256, always fits into uint256
        value = (val >> (232 - (mantissaType << 4))) * (10 ** exponent);
        // Number of bytes read is 1 (for type and exponent) + (3 + 2 * type) (for mantissa) = 4 + 2 * type
        parsedBytes = (mantissaType << 1) + 4;
    }

    /// @dev Parse the compressed data which contain isAsk and orderBookId from a single byte
    /// @param startByte Index of startByte of calldata
    /// @param msgDataLength Length of the data bytes in msg
    function _parseCompressedOBFromCallData(
        uint256 startByte,
        uint256 msgDataLength
    ) internal pure returns (bool isAsk, uint8 orderBookId) {
        if (startByte >= msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }

        uint256 val;
        assembly {
            val := calldataload(startByte)
        }

        val = val >> (256 - 8);
        isAsk = ((val) & (1 << 7)) > 0;
        orderBookId = uint8(val) & ((1 << 7) - 1);
    }

    /// @notice Parse for number at specific startByte of calldata
    /// @dev First 3 bits are used to indicate the number of extraBytes, maximum number that
    /// can be represented is 61 bits (remaining 5 bits of extraBytes + 7 bytes)
    /// @param startByte Index of startByte of calldata
    /// @param msgDataLength Length of the data bytes in msg
    /// @return value Parsed number, taking into consideration extraBytes
    /// @return parsedBytes Number of bytes read
    function _parseSizePaddedNumberFromCallData(
        uint256 startByte,
        uint256 msgDataLength
    ) internal pure returns (uint256 value, uint8 parsedBytes) {
        if (startByte >= msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }
        uint256 val;
        assembly {
            val := calldataload(startByte)
        }

        // Split bits which are part of padding
        uint256 extraBytes = (val & ((7) << 253));

        // Remove padding from number
        val ^= extraBytes;

        // Get actual extraBytes number
        extraBytes >>= 253;

        if (startByte + extraBytes >= msgDataLength) {
            revert PeripheryErrors.LighterV2ParseCallData_CannotReadPastEndOfCallData();
        }

        // Parse number, taking into consideration extraBytes
        value = (val) >> (248 - (extraBytes << 3));

        parsedBytes = uint8(++extraBytes);
    }

    /// @inheritdoc IRouter
    function getPaginatedOrders(
        uint8 orderBookId,
        uint32 startOrderId,
        bool isAsk,
        uint32 limit
    ) external view override returns (IOrderBook.OrderQueryItem memory orderData) {
        return _getOrderBookFromId(orderBookId).getPaginatedOrders(startOrderId, isAsk, limit);
    }

    /// @inheritdoc IRouter
    function getLimitOrders(
        uint8 orderBookId,
        uint32 limit
    )
        external
        view
        override
        returns (IOrderBook.OrderQueryItem memory askOrders, IOrderBook.OrderQueryItem memory bidOrders)
    {
        IOrderBook orderBook = _getOrderBookFromId(orderBookId);
        return (orderBook.getPaginatedOrders(0, true, limit), orderBook.getPaginatedOrders(0, false, limit));
    }

    /// @inheritdoc IRouter
    function suggestHintId(uint8 orderBookId, uint64 priceBase, bool isAsk) external view override returns (uint32) {
        return _getOrderBookFromId(orderBookId).suggestHintId(priceBase, isAsk);
    }

    /// @inheritdoc IRouter
    function getQuoteForExactInput(
        uint8 orderBookId,
        bool isAsk,
        uint256 amount
    ) external view override returns (uint256 quotedInput, uint256 quotedOutput) {
        return factory.getQuoteForExactInput(orderBookId, isAsk, amount);
    }

    /// @inheritdoc IRouter
    function getQuoteForExactOutput(
        uint8 orderBookId,
        bool isAsk,
        uint256 amount
    ) external view override returns (uint256 quotedInput, uint256 quotedOutput) {
        return factory.getQuoteForExactOutput(orderBookId, isAsk, amount);
    }

    /// @inheritdoc IRouter
    function getQuoteForExactInputMulti(
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactInput
    ) external view override returns (uint256 quotedInput, uint256 quotedOutput) {
        // validateMultiPathSwap throws in case of error
        factory.validateMultiPathSwap(swapRequests);

        return factory.getQuoteForExactInputMulti(swapRequests, exactInput);
    }

    /// @inheritdoc IRouter
    function getQuoteForExactOutputMulti(
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactOutput
    ) external view override returns (uint256 quotedInput, uint256 quotedOutput) {
        // validateMultiPathSwap throws in case of error
        factory.validateMultiPathSwap(swapRequests);

        return factory.getQuoteForExactOutputMulti(swapRequests, exactOutput);
    }

    /// @inheritdoc IRouter
    function validateMultiPathSwap(SwapRequest[] memory swapRequests) external view override {
        factory.validateMultiPathSwap(swapRequests);
    }

    /// @dev Returns IOrderBook for given order book id using factory
    function _getOrderBookFromId(uint8 orderBookId) internal view returns (IOrderBook) {
        address orderBookAddress = factory.getOrderBookFromId(orderBookId);
        if (orderBookAddress == address(0)) {
            revert PeripheryErrors.LighterV2Router_InvalidOrderBookId();
        }
        return IOrderBook(orderBookAddress);
    }
}

