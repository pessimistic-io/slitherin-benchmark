// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./ProbabilityType.sol";

abstract contract IConfigStorage {
    struct Config {
        address vrfCoordinator;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        // segment
        uint16 requestConfirmations;
        uint16 reserved;
        /// Share of jackpot send to winner.
        Probability jackpotShare;
        Probability jackpotPriceShare;
        address signer;
        // TODO: 32 left
        // segment
        bytes32 keyHash;
        // stub (320 bytes)
        bytes32[10] _placeHolder;
    }

    function _config() internal virtual view returns (Config storage);
}

