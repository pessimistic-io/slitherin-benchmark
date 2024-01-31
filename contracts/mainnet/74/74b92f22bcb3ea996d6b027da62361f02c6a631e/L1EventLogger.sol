// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IL1EventLogger.sol";
import "./IL1EventLoggerEvents.sol";
import "./EventLogger.sol";

contract L1EventLogger is EventLogger, IL1EventLogger, IL1EventLoggerEvents {
    function emitClaimEtherForMultipleNftsMessageSent(
        bytes32 canonicalNftsHash_,
        bytes32 tokenIdsHash_,
        address beneficiary_
    ) external {
        emit ClaimEtherForMultipleNftsMessageSent(
            msg.sender,
            canonicalNftsHash_,
            tokenIdsHash_,
            beneficiary_
        );
    }

    function emitMarkReplicasAsAuthenticMessageSent(
        address canonicalNft_,
        uint256 tokenId_
    ) external {
        emit MarkReplicasAsAuthenticMessageSent(
            msg.sender,
            canonicalNft_,
            tokenId_
        );
    }
}

