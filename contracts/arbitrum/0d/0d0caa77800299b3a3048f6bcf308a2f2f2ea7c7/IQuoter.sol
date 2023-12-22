// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IRouteQuoterParameters.sol";

/// @title Quoter Interface
/// @notice Supports the ability to quote the calculated amounts from exact input or exact output swaps
/// @notice For each grid also tells you the number of initialized boundaries crossed and the price of the grid after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting to compute
/// the result. They are also not gas efficient and should not be called on-chain.
interface IQuoter is IRouteQuoterParameters {
    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The swap path (each token pair and the payload of its grid)
    /// @param amountIn The amount of the first token to be swapped
    /// @return amountOut The amount of the last token to be received
    /// @return amountInList A list of the amountIn for each grid in the path
    /// @return priceX96AfterList The price list of each grid in the path after the swap
    /// @return initializedBoundariesCrossedList The list of initialized Boundaries crossed by the swap for each grid in the path
    /// @return gasEstimate That the swap may consume
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    )
        external
        returns (
            uint256 amountOut,
            uint256[] memory amountInList,
            uint160[] memory priceX96AfterList,
            uint32[] memory initializedBoundariesCrossedList,
            uint256 gasEstimate
        );

    /// @notice Returns the amount out received for a given exact input for a swap of a single grid
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// @return result The result of the quote, encoded as `QuoteExactResult`
    function quoteExactInputSingle(
        QuoteExactInputSingleParameters memory params
    ) external returns (QuoteExactResult memory result);

    /// @notice Returns the amount out received and amount in for a given exact input for a swap of a single grid
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// @return result The result of the quote, encoded as `QuoteExactResult`
    function quoteExactInputSingleWithAmountIn(
        QuoteExactInputSingleParameters memory params
    ) external returns (QuoteExactResult memory result);

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    /// @param path The swap path (each token pair and the payload of its grid).
    /// The path must be provided in reverse
    /// @param amountOut The amount of the last token to be received
    /// @return amountIn The amount of the first token to be swapped
    /// @return amountOutList A list of the amountOut for each grid in the path
    /// @return priceX96AfterList The price list of each grid in the path after the swap
    /// @return initializedBoundariesCrossedList List of the initialized boundaries that the swap crossed for each grid in the path
    /// @return gasEstimate That the swap may consume
    function quoteExactOutput(
        bytes memory path,
        uint256 amountOut
    )
        external
        returns (
            uint256 amountIn,
            uint256[] memory amountOutList,
            uint160[] memory priceX96AfterList,
            uint32[] memory initializedBoundariesCrossedList,
            uint256 gasEstimate
        );

    /// @notice Returns the amount in required to receive the given exact output amount for a swap of a single grid
    /// @param params The params for the quote, encoded as `QuoteExactOutputSingleParams`
    /// @return result The result of the quote, encoded as `QuoteExactResult`
    function quoteExactOutputSingle(
        QuoteExactOutputSingleParameters memory params
    ) external returns (QuoteExactResult memory result);
}

