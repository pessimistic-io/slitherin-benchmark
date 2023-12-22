// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// ----------------------------------------------------------- BASE SOCKET ORDER ----------------------------------------------------------- //

/**
 * @notice BasicInfo is basic information needed in the socket invariant to post an order.
 * @notice This is the very basic info needed in every order.
 * @param sender - address of the order creator.
 * @param inputToken - address of the token on source.
 * @param inputAmount - amount of the input token the user wants to sell.
 * @param deadline - timestamp till the order is valid.
 * @param nonce - unique number that cannot be repeated.
 */
struct BasicInfo {
    address sender;
    address inputToken;
    uint256 inputAmount;
    uint256 deadline; // till when is the order valid.
    uint256 nonce;
}

/**
 * @notice SocketOrder is the order against which the user is signing to interact with socket protocol.
 * @notice This order will be exposed to all the solvers in socket protocol.
 * @param info - Basic Info Struct from the order above.
 * @param receiver - address where the funds will be sent when fulfilled or the contract where the payload given will be executed.
 * @param outputToken - address of the token to be fulfilled with on the destination.
 * @param minOutputAmount - the absolute minimum amount of output token the user wants to buy.
 * @param fromChainId -  source chain id where the order is made.
 * @param toChainId -  destChainId where the order will be fulfilled.
 */
struct SocketOrder {
    BasicInfo info;
    address receiver;
    address outputToken;
    uint256 minOutputAmount;
    uint256 fromChainId;
    uint256 toChainId;
}

// ----------------------------------------------------------- RFQ ORDERS ----------------------------------------------------------- //

/**
 * @notice RFQ Order is the order being filled by a whitelisted RFQ Solver.
 * @param order - The base socket order against which the user signed.
 * @param promisedAmount - amount promised by the solver on the destination.
 * @param userSignature - signature of the user against the socket order.
 */
struct RFQOrder {
    SocketOrder order;
    uint256 promisedAmount;
    bytes userSignature;
}

/**
 * @notice Batch RFQ Order is the batch of rfq orders being submitted by an rfq solver.
 * @param settlementReceiver - address that will receive the user funds on the source side when order is settled.
 * @param orders - RFQ orders in the batch.
 * @param socketSignature - batch order signed by Socket so that the auction winner can only submit the orders won in auction.
 */
struct BatchRFQOrder {
    address settlementReceiver;
    RFQOrder[] orders;
    bytes socketSignature;
}

/**
 * @notice Fulfill RFQ Order is the order being fulfilled on the destiantion by any solver.
 * @param order - order submitted by the user on the source side.
 * @param amount - amount to fulfill the user order on the destination.
 */
struct FulfillRFQOrder {
    SocketOrder order;
    uint256 amount;
}

/**
 * @notice Batch Gateway Orders is the batch of gateway orders being submitted by the gateway solver.
 * @param info - Gateway orders in the batch.
 * @param settlementReceiver - address that will receive funds when an order is settled.
 * @param promisedAmount - amount promised by the solver.
 */
struct ExtractedRFQOrder {
    BasicInfo info;
    address settlementReceiver;
    uint256 promisedAmount;
    uint256 fulfillDeadline;
}

// ----------------------------------------------------------- GATEWAY ORDERS ----------------------------------------------------------- //

/**
 * @notice Gateway Order is the order being filled by a whitelisted Gateway Solver.
 * @notice This order will be routed through the socket gateway using an external bridge.
 * @param order - The base socket order against which the user signed.
 * @param gatewayValue - value to be sent to socket gateway if needed.
 * @param gatewayPayload - calldata supposed to be sent to to socket gateway for bridging.
 * @param userSignature - signature of the user against the socket order.
 */
struct GatewayOrder {
    SocketOrder order;
    uint256 gatewayValue;
    bytes gatewayPayload;
    bytes userSignature;
}

/**
 * @notice Batch Gateway Orders is the batch of gateway orders being submitted by the gateway solver.
 * @param orders - Gateway orders in the batch.
 * @param socketSignature - batch order signed by Socket so that the auction winner can only submit the orders won in auction.
 */
struct BatchGatewayOrder {
    GatewayOrder[] orders;
    bytes socketSignature;
}

