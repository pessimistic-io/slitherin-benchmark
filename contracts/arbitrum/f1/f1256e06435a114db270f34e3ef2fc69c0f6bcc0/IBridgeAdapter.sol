// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBridgeAdapter {
    /// @notice Struct with token info for bridge.
    /// @notice `address_` - token address.
    /// @notice `amount` - token amount.
    /// @notice `slippage` - slippage for bridge.
    /// @dev Slippage should be in bps (eg 100% = 1e4)
    struct Token {
        address address_;
        uint256 amount;
        uint256 slippage;
    }

    /// @notice Struct with message info for bridge.
    /// @notice `dstChainId` - evm chain id (check http://chainlist.org/ for reference)
    /// @notice `content` - any info about bridge (eg `abi.encode(chainId, msg.sender)`)
    /// @notice `bridgeParams` - bytes with bridge params, different for each bridge implementation
    struct Message {
        uint256 dstChainId;
        bytes content;
        bytes bridgeParams;
    }

    /// @notice Event emitted when bridge finished on destination chain
    /// @param traceId trace id from `sendTokenWithMessage`
    /// @param token bridged token address
    /// @param amount bridge token amount
    event BridgeFinished(
        bytes32 indexed traceId,
        address token,
        uint256 amount
    );

    /// @notice Reverts, if bridge finished with wrong caller
    error Unauthorized();

    /// @notice Reverts, if chain not supported with this bridge adapter
    /// @param chainId Provided chain id
    error UnsupportedChain(uint256 chainId);

    /// @notice Reverts, if token not supported with this bridge adapter
    /// @param token Provided token address
    error UnsupportedToken(address token);

    /// @notice Send custom token with message to antoher evm chain.
    /// @dev Caller contract should be deployed on same addres on destination chain.
    /// @dev Caller contract should send target token before call.
    /// @dev Caller contract should implement `ITokenWithMessageReceiver`.
    /// @param token Struct with token info.
    /// @param token Struct with token info1.
    /// @param message Struct with message info.
    /// @return traceId Random bytes32 for bridge tracing.
    function sendTokenWithMessage(
        Token calldata token,
        Message calldata message
    ) external payable returns (bytes32 traceId);

    /// @notice Estimate fee in native currency for `sendTokenWithMessage`.
    /// @dev You should provide equal params to `estimateFee` and `sendTokenWithMessage`
    /// @param token Struct with token info.
    /// @param message Struct with message info.
    /// @return fee Fee amount in native currency
    function estimateFee(
        Token calldata token,
        Message calldata message
    ) external view returns (uint256 fee);

    /// @notice Returns block containing bridge finishing transaction.
    /// @param traceId trace id from `sendTokenWithMessage`
    /// @return blockNumber block number in destination chain
    function bridgeFinishedBlock(
        bytes32 traceId
    ) external view returns (uint256 blockNumber);
}

