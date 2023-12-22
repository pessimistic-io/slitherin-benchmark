// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Context} from "./Context.sol";
import {IGovernanceMessageHandler} from "./IGovernanceMessageHandler.sol";
import {ITelepathyHandler} from "./ITelepathyHandler.sol";

error NotRouter(address sender, address router);
error InvalidSourceChainId(uint32 sourceChainId, uint32 expectedSourceChainId);
error InvalidGovernanceMessageVerifier(address governanceMessagerVerifier, address expectedGovernanceMessageVerifier);

abstract contract GovernanceMessageHandler is IGovernanceMessageHandler, Context {
    address public immutable telepathyRouter;
    address public immutable governanceMessageVerifier;
    uint32 public immutable allowedSourceChainId;

    constructor(address telepathyRouter_, address governanceMessageVerifier_, uint32 allowedSourceChainId_) {
        telepathyRouter = telepathyRouter_;
        governanceMessageVerifier = governanceMessageVerifier_;
        allowedSourceChainId = allowedSourceChainId_;
    }

    function handleTelepathy(uint32 sourceChainId, address sourceSender, bytes memory data) external returns (bytes4) {
        address msgSender = _msgSender();
        if (msgSender != telepathyRouter) revert NotRouter(msgSender, telepathyRouter);
        // NOTE: we just need to check the address that called the telepathy router (GovernanceMessageVerifier)
        // and not who emitted the event on Polygon since it's the GovernanceMessageVerifier that verifies that
        // a certain event has been emitted by the GovernanceStateReader
        if (sourceChainId != allowedSourceChainId) {
            revert InvalidSourceChainId(sourceChainId, allowedSourceChainId);
        }
        if (sourceSender != governanceMessageVerifier) {
            revert InvalidGovernanceMessageVerifier(sourceSender, governanceMessageVerifier);
        }

        _onGovernanceMessage(data);

        return ITelepathyHandler.handleTelepathy.selector;
    }

    function _onGovernanceMessage(bytes memory message) internal virtual {}
}

