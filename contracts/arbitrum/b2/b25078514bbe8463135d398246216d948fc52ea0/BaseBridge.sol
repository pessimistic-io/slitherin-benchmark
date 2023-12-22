// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./IConfig.sol";
import "./IRegistry.sol";
import "./IBridge.sol";
import "./ISocketRegistry.sol";

abstract contract BaseBridge is IBridge {
    using SafeERC20 for IERC20Metadata;

    IConfig public immutable override config;

    constructor(IConfig c) {
        config = c;
    }

    // non payable as we only handle stablecoins
    function outboundERC20TransferAllTo(
        BridgeAllUserRequest calldata request,
        uint256 toAmount
    ) external override {
        require(request.receiverAddress != address(0), "PT2");
        require(request.toChainId != 0, "PT3");
        uint256 amount = IERC20Metadata(request.middlewareRequest.inputToken)
            .balanceOf(address(this));
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

    function _outboundERC20TransferTo(
        ISocketRegistry.UserRequest memory request
    ) internal virtual;
}

