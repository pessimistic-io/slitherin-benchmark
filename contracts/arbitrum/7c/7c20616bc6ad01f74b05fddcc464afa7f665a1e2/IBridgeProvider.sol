/**
 * Interface for a bridge provider
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Main.sol";
import "./ERC20_IERC20.sol";

interface ITokenBridge {
    function bridgeHxroPayloadWithTokens(
        bytes32 destToken,
        uint256 amount,
        address msgSender,
        bytes calldata hxroPayload
    ) external returns (BridgeResult memory);
}

interface IPayloadBridge {
    function bridgeHXROPayload(
        bytes calldata hxroPayload,
        address msgSender
    ) external returns (BridgeResult memory);
}

