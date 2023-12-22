// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { HedgersStorage, Hedger } from "./HedgersStorage.sol";
import { HedgersInternal } from "./HedgersInternal.sol";
import { IHedgersEvents } from "./IHedgersEvents.sol";

contract Hedgers is IHedgersEvents {
    using HedgersStorage for HedgersStorage.Layout;

    /* ========== VIEWS ========== */

    function getHedgerByAddress(address _hedger) external view returns (bool success, Hedger memory hedger) {
        return HedgersInternal.getHedgerByAddress(_hedger);
    }

    function getHedgers() external view returns (Hedger[] memory hedgerList) {
        return HedgersInternal.getHedgers();
    }

    function getHedgersLength() external view returns (uint256 length) {
        return HedgersInternal.getHedgersLength();
    }

    /* ========== WRITES ========== */

    function enlist() external returns (Hedger memory hedger) {
        HedgersStorage.Layout storage s = HedgersStorage.layout();

        require(msg.sender != address(0), "Invalid address");
        require(s.hedgerMap[msg.sender].addr != msg.sender, "Hedger already exists");

        hedger = Hedger(msg.sender);
        s.hedgerMap[msg.sender] = hedger;
        s.hedgerList.push(hedger);

        emit Enlist(msg.sender, block.timestamp);
    }
}

