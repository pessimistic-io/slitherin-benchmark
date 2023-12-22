// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./IOrderBook.sol";
import "./IFactory.sol";
import "./PeripheryErrors.sol";
import "./ISwapMultiRequest.sol";

/// @title Quoter provides quoting functionality for swaps
library QuoterLib {
    /// @notice Structure to hold local variables for internal functions
    struct LocalVars {
        uint32 index; // Index of the orders in OrderBook
        uint256 filledAmount0; // Total filledAmount of token0 in the swap
        uint256 filledAmount1; // Total filledAmount of token1 in the swap
        uint256 amount; // Remaining amount for swapExact function
        uint256 exactInput; // exactInput amount used for swapExactInput
        uint256 exactOutput; // exactOutput amount used for swapExactOutput
        uint256 swapAmount0; // Swapped amount for token0 during a single match
        uint256 swapAmount1; // Swapped amount for token1 during a single match
        bool fullTakerFill; // Boolean indicator to mark if taker swap is fully filled
    }

    /// @notice Returns quote for exact input single swap
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param orderBookId Id of the orderBook
    /// @param isAsk Whether the order is an ask order
    /// @param exactInput Amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput The amount of token required for swap
    /// @return quotedOutput The amount of token to be received by the user
    function getQuoteForExactInput(
        IFactory factory,
        uint8 orderBookId,
        bool isAsk,
        uint256 exactInput
    ) internal view returns (uint256 quotedInput, uint256 quotedOutput) {
        return getQuote(factory, orderBookId, isAsk, exactInput, true);
    }

    /// @notice Returns quote for exact output single swap
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param orderBookId Id of the orderBook
    /// @param isAsk Whether the order is an ask order
    /// @param exactOutput Amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput The amount of token required for swap
    /// @return quotedOutput The amount of token to be received by the user
    function getQuoteForExactOutput(
        IFactory factory,
        uint8 orderBookId,
        bool isAsk,
        uint256 exactOutput
    ) internal view returns (uint256 quotedInput, uint256 quotedOutput) {
        return getQuote(factory, orderBookId, isAsk, exactOutput, false);
    }

    /// @notice Returns quote for exact input swap with multiple hops (multi path)
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param swapRequests Array of swap requests defining the multi path swap sequence
    /// @param exactInput Amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput The initial amount of token required for swap
    /// @return quotedOutput The final amount of token to be received by the user
    function getQuoteForExactInputMulti(
        IFactory factory,
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactInput
    ) internal view returns (uint256 quotedInput, uint256 quotedOutput) {
        LocalVars memory localVars;
        uint256 requestLength = swapRequests.length;
        uint256 index = 0;

        while (true) {
            (localVars.exactInput, localVars.exactOutput) = getQuoteForExactInput(
                factory,
                swapRequests[index].orderBookId,
                swapRequests[index].isAsk,
                exactInput
            );

            // First order book in the swapRequest path is used to set quotedInput
            if (index == 0) {
                quotedInput = localVars.exactInput;
            }

            if (index + 1 < requestLength) {
                // exactInput for next request to process should be the exactOutput of the current swap
                exactInput = localVars.exactOutput;
                unchecked {
                    ++index;
                }
            } else {
                // Last order book in the swapRequest path is used to set quotedOutput
                quotedOutput = localVars.exactOutput;
                break;
            }
        }

        return (quotedInput, quotedOutput);
    }

    /// @notice Returns quote for exact output swap with multiple hops (multi path)
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param swapRequests Array of swap requests defining the multi path swap sequence
    /// @param exactOutput Amount of token to get quote for (token0 or token1 based on isAsk)
    /// @return quotedInput The initial amount of token required for swap
    /// @return quotedOutput The final amount of token to be received by the user
    function getQuoteForExactOutputMulti(
        IFactory factory,
        ISwapMultiRequest.SwapRequest[] memory swapRequests,
        uint256 exactOutput
    ) internal view returns (uint256 quotedInput, uint256 quotedOutput) {
        LocalVars memory localVars;
        uint256 requestLength = swapRequests.length;
        uint256 index = requestLength - 1;

        // To be able to calculate quotedInput for given exact output, iterate over the swapRequests in reverse order
        while (true) {
            (localVars.exactInput, localVars.exactOutput) = getQuoteForExactOutput(
                factory,
                swapRequests[index].orderBookId,
                swapRequests[index].isAsk,
                exactOutput
            );

            // Last order book in the swapRequest path is used to set quotedOutput
            if (index + 1 == requestLength) {
                quotedOutput = localVars.exactOutput;
            }

            if (index > 0) {
                // exactOutput for next request to process (previous one in the list due to reversed order) should be the exactInput of the current swap
                exactOutput = localVars.exactInput;
                unchecked {
                    index--;
                }
            } else {
                // First order book in the swapRequest path is used to set quotedInput
                quotedInput = localVars.exactInput;
                break;
            }
        }

        return (quotedInput, quotedOutput);
    }

    /// @notice Calculates and returns swap quotes for the given order book and amount
    /// @dev Executes order book swap matching as in the given order book contract but does not change the state
    /// and returns quotedInput and quotedOutput
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param orderBookId Id of the orderBook
    /// @param isAsk Whether the order is an ask order
    /// @param amount Exact amount to get quote for (token0 or token1 based on isAsk and isExactInput)
    /// @param isExactInput Boolean indicator to mark if the amount is exactInput or exactOutput
    /// @return quotedInput Exact amount of input token to be provided
    /// @return quotedOutput Exact amount of output token to be received
    function getQuote(
        IFactory factory,
        uint8 orderBookId,
        bool isAsk,
        uint256 amount,
        bool isExactInput
    ) internal view returns (uint256, uint256) {
        IOrderBook orderBook = IOrderBook(factory.getOrderBookFromId(orderBookId));
        if (address(orderBook) == address(0)) {
            revert PeripheryErrors.LighterV2Quoter_InvalidOrderBookId();
        }

        LocalVars memory localVars;
        localVars.amount = amount;

        localVars.index = orderBook.getLimitOrder(!isAsk, 0).next;
        localVars.fullTakerFill = amount == 0;

        while (localVars.index != 1 && !localVars.fullTakerFill) {
            IOrderBook.LimitOrder memory bestMatch = isAsk
                ? orderBook.getLimitOrder(false, localVars.index)
                : orderBook.getLimitOrder(true, localVars.index);

            (localVars.swapAmount0, localVars.swapAmount1, , localVars.fullTakerFill) = (isAsk == isExactInput)
                ? orderBook.getSwapAmountsForToken0(localVars.amount, isAsk, bestMatch.amount0Base, bestMatch.priceBase)
                : orderBook.getSwapAmountsForToken1(
                    localVars.amount,
                    isAsk,
                    bestMatch.amount0Base,
                    bestMatch.priceBase
                );

            if (localVars.swapAmount0 == 0 || localVars.swapAmount1 == 0) break;

            localVars.filledAmount0 += localVars.swapAmount0;
            localVars.filledAmount1 += localVars.swapAmount1;

            if (localVars.fullTakerFill) {
                break;
            }

            localVars.amount = (isAsk == isExactInput)
                ? localVars.amount - localVars.swapAmount0
                : localVars.amount - localVars.swapAmount1;
            localVars.index = bestMatch.next;
        }

        if (!localVars.fullTakerFill) {
            revert PeripheryErrors.LighterV2Quoter_NotEnoughLiquidity();
        }

        if (isAsk) {
            return (localVars.filledAmount0, localVars.filledAmount1);
        } else {
            return (localVars.filledAmount1, localVars.filledAmount0);
        }
    }

    /// @notice Validates a multi path swap request
    /// @param factory Contract used for getting IOrderBook from orderBookId
    /// @param swapRequests Array of swap requests defining the multi path swap sequence
    function validateMultiPathSwap(
        IFactory factory,
        ISwapMultiRequest.SwapRequest[] memory swapRequests
    ) internal view {
        address lastOutput;

        for (uint256 index = 0; index < swapRequests.length; ) {
            ISwapMultiRequest.SwapRequest memory swapRequest = swapRequests[index];

            // Gets the order book associated with the current swap request in the path
            IOrderBook orderBook = IOrderBook(factory.getOrderBookFromId(swapRequest.orderBookId));

            if (address(orderBook) == address(0)) {
                revert PeripheryErrors.LighterV2Quoter_InvalidSwapExactMultiRequestCombination();
            }

            address currentInput;
            address currentOutput;

            (currentInput, currentOutput) = (swapRequest.isAsk)
                ? (address(orderBook.token0()), address(orderBook.token1()))
                : (address(orderBook.token1()), address(orderBook.token0()));

            // Checks if input token of the current swap request matches with the output token of the previous swap request
            if (index != 0 && lastOutput != currentInput) {
                revert PeripheryErrors.LighterV2Quoter_InvalidSwapExactMultiRequestCombination();
            }
            lastOutput = currentOutput;

            unchecked {
                ++index;
            }
        }
    }
}

