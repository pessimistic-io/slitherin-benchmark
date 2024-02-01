// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./LibArbitrumL1.sol";
import "./messengers_IInbox.sol";
import "./messengers_IBridge.sol";
import "./messengers_IOutbox.sol";
import "./Connector.sol";

contract L1ArbitrumConnector is Connector {
    address public inbox;

    constructor(address target, address _inbox) Connector(target) {
        inbox = _inbox;
    }

    function _forwardCrossDomainMessage() internal override {
        uint256 submissionFee = IInbox(inbox).calculateRetryableSubmissionFee(msg.data.length, 0);
        // ToDo: where to pay this fee from?
        IInbox(inbox).unsafeCreateRetryableTicket{value: submissionFee}(
            counterpart,
            0,
            submissionFee,
            address(0),
            address(0),
            0,
            0,
            msg.data
        );
    }

    function _verifyCrossDomainSender() internal override view {
        IBridge bridge = IInbox(inbox).bridge();
        address crossChainSender = LibArbitrumL1.crossChainSender(address(bridge));
        if (crossChainSender != counterpart) revert NotCounterpart();
    }
}

