// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieAggregator} from "./LibMagpieAggregator.sol";

error ReentrantCall();
error InvalidDelegatedCall();

enum DelegatedCallType {
    BridgeIn,
    BridgeOut,
    DataTransferIn,
    DataTransferOut
}

library LibGuard {
    function enforcePreGuard() internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        if (s.guarded) {
            revert ReentrantCall();
        }

        s.guarded = true;
    }

    function enforcePostGuard() internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.guarded = false;
    }

    function enforceDelegatedCallPreGuard(DelegatedCallType delegatedCallType) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        if (s.delegatedCalls[uint8(delegatedCallType)]) {
            revert ReentrantCall();
        }

        s.delegatedCalls[uint8(delegatedCallType)] = true;
    }

    function enforceDelegatedCallGuard(DelegatedCallType delegatedCallType) internal view {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        if (!s.delegatedCalls[uint8(delegatedCallType)]) {
            revert InvalidDelegatedCall();
        }
    }

    function enforceDelegatedCallPostGuard(DelegatedCallType delegatedCallType) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.delegatedCalls[uint8(delegatedCallType)] = false;
    }
}

