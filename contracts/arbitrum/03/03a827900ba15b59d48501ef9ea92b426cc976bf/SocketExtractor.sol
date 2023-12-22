// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {IPlug} from "./IPlug.sol";
import {ISocket} from "./ISocket.sol";
import {Ownable} from "./Ownable.sol";
import {BatchGatewayOrder, BatchRFQOrderWithSwap, ExtractedAndSwapped, FulfillRFQOrder, BatchRFQOrder, GatewayOrder, RFQOrder, SocketOrder, BasicInfo, ExtractedRFQOrder, RFQOrderWithSwap} from "./SocketStructs.sol";
import {ISocketWhitelist} from "./ISocketWhitelist.sol";
import {Permit2Lib} from "./Permit2Lib.sol";
import {SocketOrderLib} from "./SocketOrderLib.sol";
import {GatewayOrderLib} from "./GatewayOrderLib.sol";
import {RFQOrderLib} from "./RFQOrderLib.sol";
import {BatchAuthenticationFailed, InvalidOrder, FulfillmentChainInvalid, SocketGatewayExecutionFailed, InvalidGatewaySolver, InvalidRFQSolver, OrderDeadlineNotMet, InvalidSenderForTheOrder, DuplicateOrderHash, PromisedAmountNotMet, WrongOutoutToken, MinOutputAmountNotMet, OrderAlreadyFulfilled, FulfillDeadlineNotMet, NonSocketMessageInbound, ExtractedOrderAlreadyUnlocked, SwapFailed} from "./Errors.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {RescueFundsLib} from "./RescueFundsLib.sol";
import {BasicInfoLib} from "./BasicInfoLib.sol";

/**
 * @title Socket Extractor
 * @notice Routes user order either through RFQ or Socket Gateway.
 * @dev User will sign against a Socket Order and whitelisted Solvers will execute bridging orders for users.
 * @dev Each solver is whitelisted by socket protocol. Every batch executed will be signed by the socket protocol.
 * @author reddyismav.
 */
contract SocketExtractor is IPlug, Ownable {
    using SafeTransferLib for ERC20;
    using SocketOrderLib for SocketOrder;
    using GatewayOrderLib for BatchGatewayOrder;
    using GatewayOrderLib for GatewayOrder;
    using RFQOrderLib for RFQOrder;
    using RFQOrderLib for BatchRFQOrder;
    using RFQOrderLib for BatchRFQOrderWithSwap;
    using BasicInfoLib for BasicInfo;

    // -------------------------------------------------- ADDRESSES THAT NEED TO BE SET -------------------------------------------------- //

    /// @notice Permit2 Contract Address.
    ISignatureTransfer public immutable PERMIT2;

    /// @notice Sokcet Whitelist Contract Address
    ISocketWhitelist public immutable SOCKET_WHITELIST;

    /// @notice Socket DL address.
    address public immutable SOCKET;

    /// @notice Socket Gateway address.
    address public immutable SOCKET_GATEWAY;

    // -------------------------------------------------- RFQ EVENTS -------------------------------------------------- //

    /// @notice event to be emitted when funds are extracted from the user for an order.
    event RFQOrderExtracted(
        bytes32 orderHash,
        address sender,
        address inputToken,
        uint256 inputAmount,
        address receiver,
        address outputToken,
        uint256 minOutputAmount,
        uint256 toChainId
    );

    /// @notice event to be emitted when order is fulfilled by a solver.
    event RFQOrderFulfilled(
        bytes32 orderHash,
        address receiver,
        address outputToken,
        uint256 fromChainId,
        uint256 fulfilledAmount
    );

    /// @notice event to be emitted when user funds are unlocked and sent to the solver.
    event RFQOrderUnlocked(
        bytes32 orderHash,
        address inputToken,
        uint256 inputAmount,
        address settlementReceiver,
        uint256 promisedAmount,
        uint256 fulfilledAmount
    );

    /// @notice event to be emitted when the user withdraws funds against his order.
    event RFQOrderWithdrawn(
        bytes32 orderHash,
        address sender,
        address inputToken,
        uint256 inputAmount
    );

    // -------------------------------------------------- Gateway EVENTS -------------------------------------------------- //

    /// @notice event to be emitted when funds are extracted from the user for an order.
    event GatewayOrderExecuted(
        bytes32 orderHash,
        address sender,
        address inputToken,
        uint256 inputAmount,
        address receiver,
        address outputToken,
        uint256 minOutputAmount,
        uint256 toChainId
    );

    // -------------------------------------------------- CONSTRUCTOR -------------------------------------------------- //

    /**
     * @notice Constructor.
     * @param _socket address that can call inbound function on this contract.
     * @param _permit2Address address of the permit 2 contract.
     * @param _socketWhitelist address of the permit 2 contract.
     */
    constructor(
        address _socket,
        address _permit2Address,
        address _socketWhitelist,
        address _socketGateway,
        address _owner
    ) Ownable(_owner) {
        SOCKET = _socket;
        SOCKET_GATEWAY = _socketGateway;
        PERMIT2 = ISignatureTransfer(_permit2Address);
        SOCKET_WHITELIST = ISocketWhitelist(_socketWhitelist);
    }

    // -------------------------------------------------- MAPPINGS -------------------------------------------------- //

    /// @notice store details of all escrows stored on this extractor
    mapping(bytes32 => ExtractedRFQOrder) public extractedRfqOrders;

    /// @notice store if the order is created previously or not.
    mapping(bytes32 => bool) public disaptchedOrders;

    /// @notice store if the order is fulfilled previously or not.
    mapping(bytes32 => uint256) public fulfilledOrderAmountMap;

    /// @notice store token id to address mapping for swap
    mapping(uint8 => address) public tokenIdToAddressMap;

    /// @notice whitelist swapProviders maps routeId to Address
    mapping(uint16 => address) public swapProviders;

    /// @notice store details of swapped tokens after extraction
    mapping(bytes32 => ExtractedAndSwapped) public extractedAndSwappedRFQOrders;

    // -------------------------------------------------- GATEWAY FUNCTION -------------------------------------------------- //

    /**
     * @dev this function is gated by socket signature.
     * @notice The winning solver will submit the batch signed by socket protocol for fulfillment.
     * @notice The batch must only contain Socket Gateway orders.
     * @notice Each order will have a permit2 signature signed by the user allowing this contract to pull funds.
     * @notice Order hash is generated and will be used as the unique identifier to map to an order.
     * @notice This order will be routed through an external bridge.
     * @param batchGateway the batch of gateway orders
     */
    function batchExtractAndBridge(
        BatchGatewayOrder calldata batchGateway
    ) external payable {
        // Check if the batch is valid.
        _isValidGatewayBatch(batchGateway);

        unchecked {
            for (uint i = 0; i < batchGateway.orders.length; i++) {
                // Return order hash if the order is valid.
                bytes32 orderHash = _isValidGatewayOrder(
                    batchGateway.orders[i]
                );

                // Transfer Funds from user using Permit2 Signature.
                _transferFundsForGateway(batchGateway.orders[i], orderHash);

                // Call Socket Gateway
                _callSocketGateway(
                    batchGateway.orders[i].gatewayValue,
                    batchGateway.orders[i].gatewayPayload,
                    batchGateway.orders[i].order.info.inputToken,
                    batchGateway.orders[i].order.info.inputAmount
                );

                // Mark the Gateway Order as dispatched.
                _markGatewayOrder(orderHash);

                // Emit the order hash for the event.
                emit GatewayOrderExecuted(
                    orderHash,
                    batchGateway.orders[i].order.info.sender,
                    batchGateway.orders[i].order.info.inputToken,
                    batchGateway.orders[i].order.info.inputAmount,
                    batchGateway.orders[i].order.receiver,
                    batchGateway.orders[i].order.outputToken,
                    batchGateway.orders[i].order.minOutputAmount,
                    batchGateway.orders[i].order.toChainId
                );
            }
        }
    }

    // -------------------------------------------------- RFQ FUNCTIONS -------------------------------------------------- //

    /**
     * @dev this function is gated by socket signature.
     * @notice The winning solver will submit the batch signed by socket protocol for fulfillment.
     * @notice The batch must only contain RFQ orders.
     * @notice Each order will have a permit2 signature signed by the user allowing this contract to pull funds.
     * @notice Order hash is generated and will be used as the unique identifier to unlock user funds after solver fills the order.
     * @notice User can unlock funds after the fulfillment deadline if the order is still unfulfilled.
     * @param batchRfq the batch of orders getting submitted for fulfillment.
     */
    function batchExtractRFQ(BatchRFQOrder calldata batchRfq) external payable {
        // Check if the batch is valid.
        _isValidRFQBatch(batchRfq);

        // Unchecked loop on batch iterating rfq orders.
        unchecked {
            for (uint i = 0; i < batchRfq.orders.length; i++) {
                // Return order hash if the order is valid.
                bytes32 orderHash = _isValidRFQOrder(batchRfq.orders[i]);

                // Transfer Funds from user using Permit2 Signature.
                _transferFundsForRFQ(batchRfq.orders[i], orderHash);

                // Save the RFQ Order against the hash.
                _saveRFQOrder(
                    batchRfq.orders[i],
                    orderHash,
                    batchRfq.settlementReceiver
                );

                // Emit the order hash for the event.
                emit RFQOrderExtracted(
                    orderHash,
                    batchRfq.orders[i].order.info.sender,
                    batchRfq.orders[i].order.info.inputToken,
                    batchRfq.orders[i].order.info.inputAmount,
                    batchRfq.orders[i].order.receiver,
                    batchRfq.orders[i].order.outputToken,
                    batchRfq.orders[i].order.minOutputAmount,
                    batchRfq.orders[i].order.toChainId
                );
            }
        }
    }

    /**
     * @dev this function is gated by socket signature.
     * @notice The winning solver will submit the batch signed by socket protocol for fulfillment.
     * @notice The batch must only contain RFQ orders.
     * @notice Each order will have a permit2 signature signed by the user allowing this contract to pull funds.
     * @notice Order hash is generated and will be used as the unique identifier to unlock user funds after solver fills the order.
     * @notice User can unlock funds after the fulfillment deadline if the order is still unfulfilled.
     * @param batchRfq the batch of orders getting submitted for fulfillment.
     */
    function batchExtractRFQWithSwap(
        BatchRFQOrderWithSwap calldata batchRfq
    ) external payable {
        // Check if the batch is valid.
        _isValidRFQBatch(batchRfq);

        // Unchecked loop on batch iterating rfq orders.
        unchecked {
            for (uint i = 0; i < batchRfq.orders.length; i++) {
                // Return order hash if the order is valid.
                bytes32 orderHash = _isValidRFQOrder(
                    batchRfq.orders[i]
                );

                // Transfer Funds from user using Permit2 Signature.
                _transferFundsForRFQ(batchRfq.orders[i], orderHash);

                // Save the RFQ Order against the hash.
                _saveRFQOrder(
                    batchRfq.orders[i],
                    orderHash,
                    batchRfq.settlementReceiver
                );

                // Emit the order hash for the event.
                emit RFQOrderExtracted(
                    orderHash,
                    batchRfq.orders[i].order.info.sender,
                    batchRfq.orders[i].order.info.inputToken,
                    batchRfq.orders[i].order.info.inputAmount,
                    batchRfq.orders[i].order.receiver,
                    batchRfq.orders[i].order.outputToken,
                    batchRfq.orders[i].order.minOutputAmount,
                    batchRfq.orders[i].order.toChainId
                );
                // perform the swap required by the solver
                _performSwap(batchRfq.orders[i], orderHash);
            }
        }
    }

    /**
     * @dev this function will be called by the solver to fulfill RFQ Orders pulled on the source side.
     * @notice Each order will have amount that will be disbursed to the receiver.
     * @notice Order hash is generated and will be used as the unique identifier to unlock user funds on the source chain.
     * @notice If the order fulfillment is wrong then the solver will lose money as the user funds will not be unlocked on the other side.
     * @notice User can unlock funds after the fulfillment deadline if the order is still unfulfilled on the source side if the message does not reach before fulfillment deadline.
     * @notice Solver when pulling funds on the source side gives a settlement receiver, this receiver will get the funds when order is settled on the source side.
     * @param fulfillOrders array of orders to be fulfilled.
     */
    function fulfillBatchRFQ(
        FulfillRFQOrder[] calldata fulfillOrders
    ) external payable {
        // Unchecked loop on fulfill orders array
        unchecked {
            for (uint i = 0; i < fulfillOrders.length; i++) {
                // Check if the toChainId in the order matches the block chainId.
                if (block.chainid != fulfillOrders[i].order.toChainId)
                    revert FulfillmentChainInvalid();

                // Create the order hash from the order info
                bytes32 orderHash = fulfillOrders[i].order.hash();

                // Check if the order is already fulfilled.
                if (fulfilledOrderAmountMap[orderHash] > 0)
                    revert OrderAlreadyFulfilled();

                // Get the solver promised amount for the user from the solver
                // The solver promised amount should be equal or more than the promised amount on the source side.
                ERC20(fulfillOrders[i].order.outputToken).safeTransferFrom(
                    msg.sender,
                    fulfillOrders[i].order.receiver,
                    fulfillOrders[i].amount
                );

                // Save fulfilled order
                fulfilledOrderAmountMap[orderHash] = fulfillOrders[i].amount;

                // emit event
                emit RFQOrderFulfilled(
                    orderHash,
                    fulfillOrders[i].order.receiver,
                    fulfillOrders[i].order.outputToken,
                    fulfillOrders[i].order.fromChainId,
                    fulfillOrders[i].amount
                );
            }
        }
    }

    /**
     * @dev this function can be called by anyone to send message back to source chain.
     * @notice Each order hash will have an amount against it.
     * @notice Array of order hashes and array of amounts will be sent back to the source chain and will be settled against.
     * @param orderHashes array of order hashes that were fulfilled on destination domain.
     * @param msgValue value being send to DL as fees.
     * @param destGasLimit gas limit to be used on the destination where message has to be executed.
     * @param srcChainId chainId of the destination where the message has to be executed.
     */
    function settleRFQOrders(
        bytes32[] calldata orderHashes,
        uint256 msgValue,
        uint256 destGasLimit,
        uint256 srcChainId
    ) external payable {
        uint256 length = orderHashes.length;
        uint256[] memory fulfillAmounts = new uint256[](length);

        unchecked {
            for (uint i = 0; i < length; i++) {
                // Get amount fulfilled for the order.
                uint256 amount = fulfilledOrderAmountMap[orderHashes[i]];

                // Check if the amount is greater than 0.
                if (amount > 0) {
                    fulfillAmounts[i] = amount;
                } else {
                    revert InvalidOrder();
                }
            }
        }

        _outbound(
            uint32(srcChainId),
            destGasLimit,
            msgValue,
            bytes32(0),
            bytes32(0),
            abi.encode(orderHashes, fulfillAmounts)
        );
    }

    /**
     * @notice User can withdraw funds if the fulfillment deadline has passed for an extracted rfq order.
     * @param orderHash order hash of the order to withdraw funds.
     */
    function withdrawRFQFunds(bytes32 orderHash) external payable {
        // Get the order against the order hash.
        ExtractedRFQOrder memory rfqOrder = extractedRfqOrders[orderHash];

        // Check if the fulfillDeadline has passed.
        if (block.timestamp < rfqOrder.fulfillDeadline)
            revert FulfillDeadlineNotMet();

        // Transfer funds to the user(sender in the order)
        ERC20(rfqOrder.info.inputToken).safeTransfer(
            rfqOrder.info.sender,
            rfqOrder.info.inputAmount
        );

        // Remove the orderHash from the extractedOrders list after releasing funds to the solver.
        delete extractedRfqOrders[orderHash];
        delete disaptchedOrders[orderHash];

        // Emit event when the user withdraws funds against the order.
        emit RFQOrderWithdrawn(
            orderHash,
            rfqOrder.info.sender,
            rfqOrder.info.inputToken,
            rfqOrder.info.inputAmount
        );
    }
    // FIXME: add docs 
    // TODO: maybe add events, check in with others if they want events
    function setTokenIdToAddressMap(uint8 tokenId, address tokenAddress) external onlyOwner {
        tokenIdToAddressMap[tokenId] = tokenAddress;
    }

    function setSwapProviders(uint16 routeId, address swapProvider) external onlyOwner {
        swapProviders[routeId] = swapProvider;
    }

    function removeSwapProviders(uint16 routeId) external onlyOwner {
        delete swapProviders[routeId];
    }

    function removeTokenIdToAddressMap(uint8 tokenId) external onlyOwner {
        delete tokenIdToAddressMap[tokenId];
    }

    // -------------------------------------------------- GATEWAY RELATED INTERNAL FUNCTIONS -------------------------------------------------- //

    /**
     * @dev checks the validity of the gateway batch being submitted.
     * @notice Reverts if the msg sender is not a whitelisted solver.
     * @notice Reverts if the socket signature is not authenticated.
     * @param batchGateway batch of gateway orders.
     */
    function _isValidGatewayBatch(
        BatchGatewayOrder calldata batchGateway
    ) internal view {
        // Check if socket protocol has signed against this order.
        if (
            !SOCKET_WHITELIST.isSocketApproved(
                batchGateway.hashBatch(),
                batchGateway.socketSignature
            )
        ) revert BatchAuthenticationFailed();

        if (!SOCKET_WHITELIST.isGatewaySolver(msg.sender))
            revert InvalidGatewaySolver();
    }

    /**
     * @dev checks the validity of the gateway order.
     * @notice Reverts if any of the checks below are not met.
     * @notice Returns the order hash
     * @param gatewayOrder gateway order.
     */
    function _isValidGatewayOrder(
        GatewayOrder calldata gatewayOrder
    ) internal view returns (bytes32 orderHash) {
        // Check if the order deadline is met.
        if (block.timestamp >= gatewayOrder.order.info.deadline)
            revert OrderDeadlineNotMet();

        // Create the order hash, order hash will be recreated on the fulfillment function.
        // This hash is solely responsible for unlocking user funds for the solver.
        orderHash = gatewayOrder.order.hash();

        // Check is someone is trying to submit the same order again.
        if (disaptchedOrders[orderHash]) revert DuplicateOrderHash();
    }

    /**
     * @dev transfer funds from the user to the contract using Permit 2.
     * @param gatewayOrder gateway order.
     * @param orderHash hash of the order signed by the user.
     */
    function _transferFundsForGateway(
        GatewayOrder calldata gatewayOrder,
        bytes32 orderHash
    ) internal {
        // Permit2 Transfer From User to this contract.
        PERMIT2.permitWitnessTransferFrom(
            Permit2Lib.toPermit(gatewayOrder.order.info),
            Permit2Lib.transferDetails(gatewayOrder.order.info, address(this)),
            gatewayOrder.order.info.sender,
            orderHash,
            SocketOrderLib.PERMIT2_ORDER_TYPE,
            gatewayOrder.userSignature
        );
    }

    /**
     * @dev function that calls gateway to bridge funds.
     * @param msgValue value to send to socket gateway.
     * @param payload calldata to send to socket gateway.
     * @param token token address that is being bridged. (used in approval)
     * @param amount amount to bridge. (used in approval)
     */
    function _callSocketGateway(
        uint256 msgValue,
        bytes calldata payload,
        address token,
        uint256 amount
    ) internal {
        // Approve Gateway For Using funds from the gateway extractor
        ERC20(token).approve(SOCKET_GATEWAY, amount);

        // Call Socket Gateway to bridge funds.
        (bool success, ) = SOCKET_GATEWAY.call{value: msgValue}(payload);

        // Revert if any of the socket gateway execution fails.
        if (!success) revert SocketGatewayExecutionFailed();
    }

    /**
     * @dev mark the order hash as dispatched.
     * @param orderHash hash of the order signed by the user.
     */
    function _markGatewayOrder(bytes32 orderHash) internal {
        // Store the Order Extracted to mark it as active.
        disaptchedOrders[orderHash] = true;
    }

    // -------------------------------------------------- RFQ RELATED INTERNAL FUNCTIONS -------------------------------------------------- //

    /**
     * @dev checks the validity of the batch being submitted.
     * @notice Reverts if the msg sender is not a whitelisted solver.
     * @notice Reverts if the socket signature is not authenticated.
     * @param batchRfq batch of rfq orders.
     */
    function _isValidRFQBatch(BatchRFQOrder calldata batchRfq) internal view {
        // Check if socket protocol has signed against this order.
        if (
            !SOCKET_WHITELIST.isSocketApproved(
                batchRfq.hashBatch(),
                batchRfq.socketSignature
            )
        ) revert BatchAuthenticationFailed();

        if (!SOCKET_WHITELIST.isRFQSolver(msg.sender))
            revert InvalidRFQSolver();
    }

    /**
     * @dev checks the validity of the batch being submitted.
     * @notice Reverts if the msg sender is not a whitelisted solver.
     * @notice Reverts if the socket signature is not authenticated.
     * @param batchRfq batch of rfq orders.
     */
    function _isValidRFQBatch(BatchRFQOrderWithSwap calldata batchRfq) internal view {
        // Check if socket protocol has signed against this order.
        if (
            !SOCKET_WHITELIST.isSocketApproved(
                batchRfq.hashBatch(),
                batchRfq.socketSignature
            )
        ) revert BatchAuthenticationFailed();

        if (!SOCKET_WHITELIST.isRFQSolver(msg.sender))
            revert InvalidRFQSolver();
    }

    /**
     * @dev checks the validity of the rfq order.
     * @notice Reverts if any of the checks below are not met.
     * @notice Returns the order hash
     * @param rfqOrder rfq order.
     */
    function _isValidRFQOrder(
        RFQOrder calldata rfqOrder
    ) internal view returns (bytes32 orderHash) {
        // Check if the order deadline is met.
        if (block.timestamp >= rfqOrder.order.info.deadline)
            revert OrderDeadlineNotMet();

        // Check if the solver promised amount is less than the output amount and revert.
        if (rfqOrder.promisedAmount < rfqOrder.order.minOutputAmount)
            revert MinOutputAmountNotMet();

        // Create the order hash, order hash will be recreated on the fulfillment function.
        // This hash is solely responsible for unlocking user funds for the solver.
        orderHash = rfqOrder.order.hash();

        // Check is someone is trying to submit the same order again.
        if (disaptchedOrders[orderHash]) revert DuplicateOrderHash();
    }

    /**
     * @dev checks the validity of the rfq order.
     * @notice Reverts if any of the checks below are not met.
     * @notice Returns the order hash
     * @param rfqOrder rfq order.
     */
    function _isValidRFQOrder(
        RFQOrderWithSwap calldata rfqOrder
    ) internal view returns (bytes32 orderHash) {
        // Check if the order deadline is met.
        if (block.timestamp >= rfqOrder.order.info.deadline)
            revert OrderDeadlineNotMet();

        // Check if the solver promised amount is less than the output amount and revert.
        if (rfqOrder.promisedAmount < rfqOrder.order.minOutputAmount)
            revert MinOutputAmountNotMet();

        // Create the order hash, order hash will be recreated on the fulfillment function.
        // This hash is solely responsible for unlocking user funds for the solver.
        orderHash = rfqOrder.order.hash();

        // Check is someone is trying to submit the same order again.
        if (disaptchedOrders[orderHash]) revert DuplicateOrderHash();
    }

    /**
     * @dev transfer funds from the user to the contract using Permit 2.
     * @param rfqOrder rfq order.
     * @param orderHash hash of the order signed by the user.
     */
    function _transferFundsForRFQ(
        RFQOrder calldata rfqOrder,
        bytes32 orderHash
    ) internal {
        // Permit2 Transfer From User to this contract.
        PERMIT2.permitWitnessTransferFrom(
            Permit2Lib.toPermit(rfqOrder.order.info),
            Permit2Lib.transferDetails(rfqOrder.order.info, address(this)),
            rfqOrder.order.info.sender,
            orderHash,
            SocketOrderLib.PERMIT2_ORDER_TYPE,
            rfqOrder.userSignature
        );
    }

    function _transferFundsForRFQ(
        RFQOrderWithSwap calldata rfqOrder,
        bytes32 orderHash
    ) internal {
        // Permit2 Transfer From User to this contract.
        PERMIT2.permitWitnessTransferFrom(
            Permit2Lib.toPermit(rfqOrder.order.info),
            Permit2Lib.transferDetails(rfqOrder.order.info, address(this)),
            rfqOrder.order.info.sender,
            orderHash,
            SocketOrderLib.PERMIT2_ORDER_TYPE,
            rfqOrder.userSignature
        );
    }

    /**
     * @dev saved the rfq order in rfq order mapping.
     * @param rfqOrder rfq order.
     * @param orderHash hash of the order signed by the user.
     * @param settlementReceiver address that will receive funds when an order is settled.
     */
    function _saveRFQOrder(
        RFQOrder calldata rfqOrder,
        bytes32 orderHash,
        address settlementReceiver
    ) internal {
        // Store the Order Extracted against the order hash.
        extractedRfqOrders[orderHash] = ExtractedRFQOrder(
            rfqOrder.order.info,
            settlementReceiver,
            rfqOrder.promisedAmount,
            block.timestamp + 86400 // 24 hours fulfill deadline. Temporary fulfill deadline.
        );
        // Store the Order Extracted to mark it as active.
        disaptchedOrders[orderHash] = true;
    }

    /**
     * @dev perform rfq swap given by the solver
     * @param rfqOrder rfq order.
     * @param orderHash hash of the order signed by the user.
     */
    function _performSwap(
        RFQOrderWithSwap calldata rfqOrder,
        bytes32 orderHash
    ) internal {
        address toToken = tokenIdToAddressMap[rfqOrder.toTokenId];

        uint256 beforeBalance = ERC20(toToken).balanceOf(address(this));

        address swapProvider = swapProviders[rfqOrder.swapProviderId];

        if(swapProvider == address(0)) {
            revert InvalidOrder();
        }

        // approve swap contract to spend from this contract
        ERC20(rfqOrder.order.info.inputToken).approve(
            swapProvider,
            rfqOrder.order.info.inputAmount
        );

        (bool success, bytes memory result) = swapProvider
            .call(rfqOrder.swapTokenData);

        if (!success) {
            revert SwapFailed();
        }

        uint256 returnAmount = abi.decode(result, (uint256));

        if (returnAmount < rfqOrder.minToTokenAmount) {
            revert SwapFailed();
        }

        uint256 afterBalance = ERC20(toToken).balanceOf(address(this));

        if (afterBalance - beforeBalance != returnAmount) {
            revert SwapFailed();
        }

        extractedAndSwappedRFQOrders[orderHash] = ExtractedAndSwapped({
            fromToken: rfqOrder.order.info.inputToken,
            fromAmount: rfqOrder.order.info.inputAmount,
            toToken: toToken,
            toAmount: returnAmount
        });
    }

    function _saveRFQOrder(
        RFQOrderWithSwap calldata rfqOrder,
        bytes32 orderHash,
        address settlementReceiver
    ) internal {
        // Store the Order Extracted against the order hash.
        extractedRfqOrders[orderHash] = ExtractedRFQOrder(
            rfqOrder.order.info,
            settlementReceiver,
            rfqOrder.promisedAmount,
            block.timestamp + 86400 // 24 hours fulfill deadline. Temporary fulfill deadline.
        );
        // Store the Order Extracted to mark it as active.
        disaptchedOrders[orderHash] = true;
    }

    /**
     * @dev saved the rfq order in rfq order mapping.
     * @param orderHash hash of the order signed by the user.
     * @param fulfilledAmount amount fulfilled on the destination.
     */
    function _settleOrder(bytes32 orderHash, uint256 fulfilledAmount) internal {
        // Check if the order hash is already unlocked.
        if (extractedRfqOrders[orderHash].promisedAmount == 0)
            revert ExtractedOrderAlreadyUnlocked();

        // Get the Extracted Order from storage.
        ExtractedRFQOrder memory rfqOrder = extractedRfqOrders[orderHash];

        // Check if the solver fulfilledAmount is not less than what was promised.
        if (fulfilledAmount < rfqOrder.promisedAmount)
            revert PromisedAmountNotMet();

        // Check if the order is under fulfillDeadline
        if (block.timestamp > rfqOrder.fulfillDeadline)
            revert FulfillDeadlineNotMet();

        if (extractedAndSwappedRFQOrders[orderHash].toAmount != 0) {
            // Release User funds to the solver against that order.
            ERC20(extractedAndSwappedRFQOrders[orderHash].toToken).safeTransfer(
                rfqOrder.settlementReceiver,
                extractedAndSwappedRFQOrders[orderHash].toAmount
            );

            delete extractedAndSwappedRFQOrders[orderHash];
        } else {
            // Release User funds to the solver against that order.
            ERC20(rfqOrder.info.inputToken).safeTransfer(
                rfqOrder.settlementReceiver,
                rfqOrder.info.inputAmount
            );
        }

        // Remove the orderHash from the extractedOrders list after releasing funds to the solver.
        delete disaptchedOrders[orderHash];
        delete extractedRfqOrders[orderHash];

        // Emit event when socket protocol releases extracted user funds to the solver.
        emit RFQOrderUnlocked(
            orderHash,
            rfqOrder.info.inputToken,
            rfqOrder.info.inputAmount,
            rfqOrder.settlementReceiver,
            rfqOrder.promisedAmount,
            fulfilledAmount
        );
    }

    // --------------------------------------------------  -------------------------------------------------- //

    // -------------------------------------------------- SOCKET DATA LAYER FUNCTIONS -------------------------------------------------- //

    function _connect(
        uint32 remoteChainSlug_,
        address remotePlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard
    ) external onlyOwner {
        ISocket(SOCKET).connect(
            remoteChainSlug_,
            remotePlug_,
            inboundSwitchboard_,
            outboundSwitchboard
        );
    }

    /**
     * @notice Function to send the message through socket data layer to the destination chain.
     * @param targetChain_ the destination chain slug to send the message to.
     * @param minMsgGasLimit_ gasLimit to use to execute the message on the destination chain.
     * @param msgValue socket data layer fees to send a message.
     * @param executionParams_ execution params.
     * @param transmissionParams_ transmission params.
     * @param payload_ payload is the encoded message that the inbound will receive.
     */
    function _outbound(
        uint32 targetChain_,
        uint256 minMsgGasLimit_,
        uint256 msgValue,
        bytes32 executionParams_,
        bytes32 transmissionParams_,
        bytes memory payload_
    ) internal {
        ISocket(SOCKET).outbound{value: msgValue}(
            targetChain_,
            minMsgGasLimit_,
            executionParams_,
            transmissionParams_,
            payload_
        );
    }

    /**
     * @notice Message received from socket DL to unlock user funds.
     * @notice Message has to be received before an orders fulfillment deadline. Solver will not unlock user funds after this deadline.
     * @param payload_ payload to be executed.
     */
    function inbound(uint32, bytes calldata payload_) external payable {
        // Check if the message is coming from the socket configured address.
        if (msg.sender != SOCKET) revert NonSocketMessageInbound();

        // Decode the payload sent after fulfillment from the other side.
        (bytes32[] memory orderHashes, uint256[] memory fulfilledAmounts) = abi
            .decode(payload_, (bytes32[], uint256[]));

        unchecked {
            for (uint i = 0; i < orderHashes.length; i++) {
                _settleOrder(orderHashes[i], fulfilledAmounts[i]);
            }
        }
    }

    // --------------------------------------------------  -------------------------------------------------- //

    // -------------------------------------------------- ADMIN FUNCTION -------------------------------------------------- //

    /**
     * @notice Rescues funds from the contract if they are locked by mistake.
     * @param token_ The address of the token contract.
     * @param rescueTo_ The address where rescued tokens need to be sent.
     * @param amount_ The amount of tokens to be rescued.
     */
    function rescueFunds(
        address token_,
        address rescueTo_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, rescueTo_, amount_);
    }

    // Gateway Batch Hash
    function getGatewayBatchHash(
        BatchGatewayOrder memory batchGateway
    ) external pure returns (bytes32 batchHash) {
        batchHash = batchGateway.hashBatch();
        return batchHash;
    }

    // RFQ Batch Hash.
    function getRFQBatchHash(
        BatchRFQOrder memory batchRfq
    ) external pure returns (bytes32 batchHash) {
        batchHash = batchRfq.hashBatch();
        return batchHash;
    }

    // Hash an RFQ order.
    function getRFQOrderHash(
        RFQOrder memory rfqOrder
    ) external pure returns (bytes32 rfqOrderHash) {
        rfqOrderHash = rfqOrder.hash();
    }

    // Hash a gateway order.
    function getGatewayOrderHash(
        GatewayOrder memory gatewayOrder
    ) external pure returns (bytes32 gatewayOrderHash) {
        gatewayOrderHash = gatewayOrder.hash();
    }

    // Get Socket Order Hash
    function getSocketOrderHash(
        SocketOrder memory order
    ) external pure returns (bytes32 orderHash) {
        orderHash = order.hash();
    }

    // Get Basic Info Hash
    function getBasicInfoHash(
        BasicInfo memory info
    ) external pure returns (bytes32 infoHash) {
        infoHash = info.hash();
    }
}

