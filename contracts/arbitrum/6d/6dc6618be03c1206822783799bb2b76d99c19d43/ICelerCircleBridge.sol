// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICelerCircleBridge - Interface for the Celer Circle Bridge operations.
/// @dev This interface provides a method for bridging them.
interface ICelerCircleBridge {
    /// @notice Deposits a specified amount of tokens for burning.
    /// @dev This function prepares tokens to be burned and sends them to a destination chain.
    /// @param amount The amount of tokens to deposit.
    /// @param dstChid The destination chain ID where the tokens will be sent.
    /// @param mintRecipient The address or identifier of the recipient on the destination chain.
    /// @param burnToken The address of the token to be burned.
    function depositForBurn(
        uint256 amount,
        uint64 dstChid,
        bytes32 mintRecipient,
        address burnToken
    ) external;
}

