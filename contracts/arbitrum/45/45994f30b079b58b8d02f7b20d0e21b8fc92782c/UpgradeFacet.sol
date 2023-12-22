// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LibPonzu} from "./LibPonzu.sol";
import {PonzuStorage, ParticipantDeposit} from "./PonzuStorage.sol";
import {WithRoles} from "./LibAccessControl.sol";
import {DEFAULT_ADMIN_ROLE} from "./AccessControlStorage.sol";
import {Participant} from "./Participant.sol";

import {AddressArrayLibUtils} from "./ArrayLibUtils.sol";


contract UpgradeFacet is WithRoles {
  using AddressArrayLibUtils for address[];

  function upgrade(uint256 time) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    uint256 totalParticipantsCount = ps.participantsList.length;
    for (uint256 i = 0; i < totalParticipantsCount; i++) {
      address participantAddress = ps.participantsList[i];
      Participant storage participant = ps.participants[participantAddress];

      uint256 participantDepositAmount = participant.oldDepositAmount +
        participant.newDepositAmount;
      if (participantDepositAmount > 0) {
        ps.participantDeposits[participantAddress] = ParticipantDeposit({
          timestamp: time,
          amount: participantDepositAmount
        });
      } else {
        ps.participantsList.swapOut(participantAddress);
        totalParticipantsCount--;
      }
    }
  }
}

