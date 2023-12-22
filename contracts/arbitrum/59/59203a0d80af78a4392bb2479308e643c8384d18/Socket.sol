// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./BaseBridge.sol";
import "./IConfig.sol";
import "./IRegistry.sol";
import "./IBridge.sol";
import "./ISocketRegistry.sol";

contract Socket is BaseBridge {
    using SafeERC20 for IERC20Metadata;

    constructor(IConfig c, IDex d) BaseBridge(c, d) {}

    // non payable as we only handle stablecoins
    function _outboundERC20TransferTo(
        ISocketRegistry.UserRequest memory request
    ) internal override {
        ISocketRegistry socketReg = config.socketRegistry();
        uint256 routeId = request.middlewareRequest.id == 0 ? request.bridgeRequest.id : request.middlewareRequest.id;
        IERC20Metadata approveToken = request.middlewareRequest.id == 0 ?
            IERC20Metadata(request.bridgeRequest.inputToken) :
            IERC20Metadata(request.middlewareRequest.inputToken);
        ISocketRegistry.RouteData memory rdata = socketReg.routes(routeId);
        address approveAddr = rdata.route;
        approveToken.safeIncreaseAllowance(approveAddr, request.amount);
        socketReg.outboundTransferTo(request);
    }
}

