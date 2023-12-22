// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./IOrderBook.sol";
import "./ISwapMultiRequest.sol";

/// @title Router Interface
/// @notice A router contract to get OrderBook Details
interface IRouter is ISwapMultiRequest {
    /// @notice Creates multiple limit orders in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to create. Size of each array given should be equal to `size`
    /// @param amount0Base The amount of token0 for each limit order in terms of number of sizeTicks.
    /// The exact amount of token0 for each order will be amount0Base[i] * sizeTick
    /// @param priceBase The price of the token0 for each limit order.
    /// Exact price for unit token0 is calculated as priceBase[i] * priceTick
    /// @param isAsk Whether each order is an ask order
    /// @param hintId Where to insert each order in the given order book. Meant to be calculated
    /// off-chain using the suggestHintId function
    /// @return orderId The id of the each created order
    function createLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint64[] memory amount0Base,
        uint64[] memory priceBase,
        bool[] memory isAsk,
        uint32[] memory hintId
    ) external returns (uint32[] memory orderId);

    /// @notice Creates a limit order in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param amount0Base The amount of token0 in terms of number of sizeTicks.
    /// The exact amount of token0 for each order will be amount0Base * sizeTick
    /// @param priceBase The price of the token0. Exact price for unit token0 is calculated as priceBase[i] * priceTick
    /// @param isAsk Whether the order is an ask order
    /// @param hintId Where to insert the order in the given order book, meant to be calculated
    /// off-chain using the suggestHintId function
    /// @return orderId The id of the created order
    function createLimitOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk,
        uint32 hintId
    ) external returns (uint32 orderId);

    /// @notice Creates a fill or kill order in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param amount0Base The amount of token0 in terms of number of sizeTicks.
    /// The exact amount of token0 for each order will be amount0Base * sizeTick
    /// @param priceBase The price of the token0. Exact price for unit token0 is calculated as priceBase[i] * priceTick
    /// @param isAsk Whether the order is an ask order
    /// @return orderId The id of the created order
    function createFoKOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk
    ) external returns (uint32 orderId);

    /// @notice Creates an immediate or cancel order in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param amount0Base The amount of token0 in terms of number of sizeTicks.
    /// The exact amount of token0 for each order will be amount0Base * sizeTick
    /// @param priceBase The price of the token0. Exact price for unit token0 is calculated as priceBase[i] * priceTick
    /// @param isAsk Whether the order is an ask order
    /// @return orderId The id of the created order
    function createIoCOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        bool isAsk
    ) external returns (uint32 orderId);

    /// @notice Cancels and creates multiple limit orders in the given order book with given parameters
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to update. Size of each array given should be equal to `size`
    /// @param orderId Id of the each order to update
    /// @param newAmount0Base The amount of token0 for each updated limit order in terms of number of sizeTicks.
    /// The exact amount of token0 for each order will be newAmount0Base[i] * sizeTick
    /// @param newPriceBase The new price of the token0 for each limit order.
    /// Exact price for unit token0 is calculated as newPriceBase[i] * priceTick
    /// @param hintId Where to insert each updated order in the given order book. Meant to be calculated
    /// off-chain using the suggestHintId function
    /// @return newOrderId The new id of the each updated order
    function updateLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId,
        uint64[] memory newAmount0Base,
        uint64[] memory newPriceBase,
        uint32[] memory hintId
    ) external returns (uint32[] memory newOrderId);

    /// @notice Cancels a limit order in the given order book and creates a new one with given parameters
    /// @param orderBookId The unique identifier of the order book
    /// @param orderId The id of the order to update
    /// @param newAmount0Base The amount of token0 for updated limit order in terms of number of sizeTicks.
    /// The exact amount of token0 will be newAmount0Base * sizeTick
    /// @param newPriceBase The new price of the token0 for updated limit order.
    /// Exact price for unit token0 is calculated as newPriceBase * priceTick
    /// @param hintId Where to insert the updated order in the given order book. Meant to
    /// be calculated off-chain using the suggestHintId function
    /// @return newOrderId The new id of the updated order
    function updateLimitOrder(
        uint8 orderBookId,
        uint32 orderId,
        uint64 newAmount0Base,
        uint64 newPriceBase,
        uint32 hintId
    ) external returns (uint32 newOrderId);

    /// @notice Cancels multiple limit orders in the given order book
    /// @dev Including an inactive order in the batch cancelation does not
    /// revert the entire transaction, function returns false for that order
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to cancel. Size of each array given should be equal to `size`
    /// @param orderId The id for each limit order to cancel
    /// @return isCanceled List of booleans indicating whether each order was successfully canceled
    function cancelLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId
    ) external returns (bool[] memory isCanceled);

    /// @notice Cancels a limit order in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param orderId The id of the order to cancel
    /// @return isCanceled A boolean indicating whether the order was successfully canceled
    function cancelLimitOrder(uint8 orderBookId, uint32 orderId) external returns (bool);

    /// @notice Performs swap in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param isAsk Whether the order is an ask order
    /// @param exactInput exactInput to pay for the swap (can be token0 or token1 based on isAsk)
    /// @param minOutput Minimum output amount expected to recieve from swap (can be token0 or token1 based on isAsk)
    /// @param recipient The address of the recipient of the output
    /// @param unwrap Boolean indicator wheter to unwrap the wrapped native token output or not
    /// @dev Unwrap is only applicable if native wrapped token is the output token
    /// @return swappedInput The amount of input taker paid for the swap
    /// @return swappedOutput The amount of output taker received from the swap
    function swapExactInputSingle(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactInput,
        uint256 minOutput,
        address recipient,
        bool unwrap
    ) external payable returns (uint256 swappedInput, uint256 swappedOutput);

    /// @notice Performs swap in the given order book
    /// @param isAsk Whether the order is an ask order
    /// @param exactOutput exactOutput to receive from the swap (can be token0 or token1 based on isAsk)
    /// @param maxInput Maximum input that the taker is willing to pay for the swap (can be token0 or token1 based on isAsk)
    /// @param recipient The address of the recipient of the output
    /// @param unwrap Boolean indicator wheter to unwrap the wrapped native token output or not
    /// @dev Unwrap is only applicable if native wrapped token is the output token
    /// @return swappedInput The amount of input taker paid for the swap
    /// @return swappedOutput The amount of output taker received from the swap
    function swapExactOutputSingle(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactOutput,
        uint256 maxInput,
        address recipient,
        bool unwrap
    ) external payable returns (uint256 swappedInput, uint256 swappedOutput);

    /// @notice Performs a multi path exact input swap
    /// @param multiPathExactInputRequest The input request containing swap details
    /// @return swappedInput The amount of input taker paid for the swap
    /// @return swappedOutput The amount of output taker received from the swap
    function swapExactInputMulti(
        MultiPathExactInputRequest memory multiPathExactInputRequest
    ) external payable returns (uint256 swappedInput, uint256 swappedOutput);

    /// @notice Performs a multi path exact output swap
    /// @param multiPathExactOutputRequest The input request containing swap details
    /// @return swappedInput The amount of input taker paid for the swap
    /// @return swappedOutput The amount of output taker received from the swap
    function swapExactOutputMulti(
        MultiPathExactOutputRequest memory multiPathExactOutputRequest
    ) external payable returns (uint256 swappedInput, uint256 swappedOutput);

    /// @notice Returns the paginated order details of ask or bid orders in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param startOrderId orderId from where the pagination should start (not inclusive)
    /// @dev caller can pass 0 to start from the top of the book
    /// @param isAsk Whether to return ask or bid orders
    /// @param limit Number number of orders to return in the page
    /// @return orderData The paginated order data
    function getPaginatedOrders(
        uint8 orderBookId,
        uint32 startOrderId,
        bool isAsk,
        uint32 limit
    ) external view returns (IOrderBook.OrderQueryItem memory orderData);

    /// @notice Returns the ask and bid order details in the given order book
    /// @param orderBookId The unique identifier of the order book
    /// @param limit Number number of orders to return from the top of the book on each side
    /// @return askOrders The list of ask order details
    /// @return bidOrders The list of bid order details
    function getLimitOrders(
        uint8 orderBookId,
        uint32 limit
    ) external view returns (IOrderBook.OrderQueryItem memory askOrders, IOrderBook.OrderQueryItem memory bidOrders);

    /// @notice Returns the order id to the right of where the new order should be inserted.
    /// Meant to be used off-chain to calculate the hintId for order operations
    /// @param orderBookId The unique identifier of the order book
    /// @param priceBase The price of the token0 for each limit order.
    /// Exact price for unit token0 is calculated as priceBase * priceTick
    /// @param isAsk Whether the order is an ask order
    /// @return hintId The id of the order to the right of where the new order should be inserted
    function suggestHintId(uint8 orderBookId, uint64 priceBase, bool isAsk) external view returns (uint32);

    /// @notice Returns quote for exact input single swap
    /// @param orderBookId The unique identifier of the order book
    /// @param isAsk Whether the order is an ask order
    /// @param exactInput amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput the amount of token required for swap
    /// @return quotedOutput the amount of token to be received by the user
    function getQuoteForExactInput(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactInput
    ) external view returns (uint256 quotedInput, uint256 quotedOutput);

    /// @notice Returns quote for exact output single swap
    /// @param orderBookId The unique identifier of the order book
    /// @param isAsk Whether the order is an ask order
    /// @param exactOutput amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput the amount of token required for swap
    /// @return quotedOutput the amount of token to be received by the user
    function getQuoteForExactOutput(
        uint8 orderBookId,
        bool isAsk,
        uint256 exactOutput
    ) external view returns (uint256 quotedInput, uint256 quotedOutput);

    /// @notice Returns quote for exact input swap multi path swap
    /// @param swapRequests array of swap requests defining the multi path swap sequence
    /// @param exactInput amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput the initial amount of token required for swap
    /// @return quotedOutput the final amount of token to be received by the user
    function getQuoteForExactInputMulti(
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactInput
    ) external view returns (uint256 quotedInput, uint256 quotedOutput);

    /// @notice Returns quote for exact output multi path swap
    /// @param swapRequests array of swap requests defining the multi path swap sequence
    /// @param exactOutput amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput the initial amount of token required for swap
    /// @return quotedOutput the final amount of token to be received by the user
    function getQuoteForExactOutputMulti(
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactOutput
    ) external view returns (uint256 quotedInput, uint256 quotedOutput);

    /// @notice Validates a multi path swap request
    /// @param swapRequests array of swap requests defining the multi path swap sequence
    function validateMultiPathSwap(SwapRequest[] memory swapRequests) external view;
}

