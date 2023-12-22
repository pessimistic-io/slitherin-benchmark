// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenWithMessageReceiver {
    /// @notice Receive bridged token with message from `BridgeAdapter`
    /// @dev Implementation should take token from caller (eg `IERC20(token).transferFrom(msg.seder, ..., amount)`)
    /// @param token Bridged token address
    /// @param amount Bridged token amount
    /// @param message Bridged message
    function receiveTokenWithMessage(
        address token,
        uint256 amount,
        bytes calldata message
    ) external;
}

