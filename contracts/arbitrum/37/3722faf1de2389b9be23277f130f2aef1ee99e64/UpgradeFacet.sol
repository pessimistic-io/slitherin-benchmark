// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./console.sol";

import {LibPonzu} from "./LibPonzu.sol";
import {PonzuStorage, ParticipantDeposit} from "./PonzuStorage.sol";
import {Participant} from "./Participant.sol";

import {Strings} from "./Strings.sol";

import {AddressArrayLibUtils} from "./ArrayLibUtils.sol";

contract UpgradeFacet {
  using AddressArrayLibUtils for address[];
  using LibPonzu for PonzuStorage;
  using Strings for uint256;
  using Strings for address;

  function migrate() external {
    // cleanup and transfer data over

    uint256 currentTime = 1683227643;

    PonzuStorage storage ps = LibPonzu.DS();
    uint256 totalParticipantsCount = ps.participantsList.length;

    uint256 i = 0;
    while (i < totalParticipantsCount) {
      address participantAddress = ps.participantsList[i];
      Participant storage participant = ps.participants[participantAddress];

      uint256 participantTotalDepositAmount = participant.oldDepositAmount +
        participant.newDepositAmount;

      if (
        participantTotalDepositAmount > 0 &&
        ps.participantDeposits[participantAddress].timestamp == 0
      ) {
        ps.participantDeposits[participantAddress] = ParticipantDeposit({
          timestamp: currentTime,
          amount: participantTotalDepositAmount
        });

        ps.newParticipantsList.push(participantAddress);
      }
      unchecked {
        ++i;
      }
    }
  }
}

