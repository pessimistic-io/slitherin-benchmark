// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./IConfig.sol";
import "./IConfig.sol";
import "./IRegistry.sol";
import "./IBridge.sol";
import "./ISocketRegistry.sol";

abstract contract BaseBridge is IBridge {
    using SafeERC20 for IERC20Metadata;

    IConfig public immutable override config;
    IDex public immutable override dex;

    constructor(IConfig c, IDex d) {
        config = c;
        dex = d;
    }
    // non payable as we only handle stablecoins
    function outboundERC20TransferAllTo(
        BridgeAllUserRequest calldata request,
        IDex.SwapAllRequest calldata swapAllRequest,
        uint256 toAmount
    ) external override {
        require(request.receiverAddress != address(0), "BB1");
        require(request.toChainId != 0, "BB2");
        uint256 amount;
        if (address(swapAllRequest.inputToken) == address(0)) {
            amount = IERC20Metadata(request.middlewareRequest.inputToken).balanceOf(address(this));
        } else {
            (bool success, bytes memory result) = address(dex).delegatecall(abi.encodeWithSelector(dex.swapAll.selector, swapAllRequest));
            require(success, string(result));
            amount = abi.decode(result, (uint256));
        }
        require(amount > 0, "PT1");
        // TODO check to make sure outboundTransferTo always reverts if outbound is not successful
        ISocketRegistry.UserRequest memory u = ISocketRegistry.UserRequest(
            request.receiverAddress,
            request.toChainId,
            amount,
            request.middlewareRequest,
            request.bridgeRequest
        );
        _outboundERC20TransferTo(u);
        // socketReg.outboundTransferTo(request);
        emit BridgeOutbound(
            request.toChainId,
            request.receiverAddress,
            u,
            toAmount
        );
    }
    // non payable as we only handle stablecoins
    function outboundERC20TransferTo(
        ISocketRegistry.UserRequest calldata request,
        IDex.SwapRequest calldata swapRequest,
        uint256 toAmount
    ) external override {
        require(request.receiverAddress != address(0), "BB1");
        require(request.toChainId != 0, "BB2");
        uint256 amount;
        if (address(swapRequest.inputToken) == address(0)) {
            amount = IERC20Metadata(request.middlewareRequest.inputToken).balanceOf(address(this));
        } else {
            (bool success, bytes memory result) = address(dex).delegatecall(abi.encodeWithSelector(dex.swap.selector, swapRequest));
            require(success, string(result));
            amount = abi.decode(result, (uint256));
        }
        require(amount > 0, "PT1");
        _outboundERC20TransferTo(ISocketRegistry.UserRequest({
            receiverAddress: request.receiverAddress,
            toChainId: request.toChainId,
            amount: amount,
            middlewareRequest: request.middlewareRequest,
            bridgeRequest: request.bridgeRequest
        }));
        // socketReg.outboundTransferTo(request);
        emit BridgeOutbound(
            request.toChainId,
            request.receiverAddress,
            request,
            toAmount
        );
    }

    function _outboundERC20TransferTo(
        ISocketRegistry.UserRequest memory request
    ) internal virtual;
}

