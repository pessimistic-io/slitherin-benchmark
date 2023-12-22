// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./ISocketRegistry.sol";
import "./IConfig.sol";
import "./ISmartAccount.sol";
import "./IDex.sol";

interface IBridge {
    event BridgeOutbound(
        uint256 indexed toChainId,
        address indexed receiverAddress,
        ISocketRegistry.UserRequest request,
        uint256 toAmount
    );

    struct BridgeAllUserRequest {
        address receiverAddress;
        uint256 toChainId;
        ISocketRegistry.MiddlewareRequest middlewareRequest;
        ISocketRegistry.BridgeRequest bridgeRequest;
    }

    function config() external view returns (IConfig);
    function dex() external view returns (IDex);

    function outboundERC20TransferAllTo(
        BridgeAllUserRequest calldata b,
        IDex.SwapAllRequest calldata swapAllRequest,
        uint256 toAmount
    ) external;
    function outboundERC20TransferTo(
        ISocketRegistry.UserRequest calldata b,
        IDex.SwapRequest calldata swapRequest,
        uint256 toAmount
    ) external;
}

