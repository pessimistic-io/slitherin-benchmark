// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { HedgersStorage, Hedger } from "./HedgersStorage.sol";

library HedgersInternal {
    using HedgersStorage for HedgersStorage.Layout;

    /* ========== VIEWS ========== */

    function getHedgerByAddress(address _hedger) internal view returns (bool success, Hedger memory hedger) {
        hedger = HedgersStorage.layout().hedgerMap[_hedger];
        return hedger.addr == address(0) ? (false, hedger) : (true, hedger);
    }

    function getHedgerByAddressOrThrow(address partyB) internal view returns (Hedger memory) {
        (bool success, Hedger memory hedger) = getHedgerByAddress(partyB);
        require(success, "Hedger is not valid");
        return hedger;
    }

    function getHedgers() internal view returns (Hedger[] memory hedgerList) {
        return HedgersStorage.layout().hedgerList;
    }

    function getHedgersLength() internal view returns (uint256 length) {
        return HedgersStorage.layout().hedgerList.length;
    }
}

