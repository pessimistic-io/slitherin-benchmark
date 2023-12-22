// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./interfaces_LinkTokenInterface.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./IInbox.sol";
import "./verification_Auth.sol";
import "./VRFRequester.sol";
import "./VRFConsumerLite.sol";

contract RandomnessRelayL2 is Auth, VRFRequester {
  address private _l1Target;
  IInbox private _inbox;
  uint256 private _requestIDs;
  mapping(uint256 => address) private _idToAddr;

  event RetryableTicketCreated(uint256 indexed ticketId);

  constructor(
    address l1Target_,
    address inbox_,
    Authority authority
  ) Auth(msg.sender, authority) {
    _l1Target = l1Target_;
    _inbox = IInbox(inbox_);
  }

  function updateL2Target(address l1Target_) external requiresAuth {
    _l1Target = l1Target_;
  }

  /// @notice only l1Target can update greeting
  function requestRandomness(uint32 wordCount)
    external
    override
    requiresAuth
    returns (uint256 requestId)
  {
    unchecked {
      _requestIDs++;
    }
    _idToAddr[_requestIDs] = msg.sender;
    // Send randomness request to ranomness relay on L1 including word count and requestID
  }

  // This is the function that should be called from the L1 to give the randomness back
  function fulfillRandomness(uint256 requestId, uint32[] memory randomWords)
    external
    requiresAuth
  {
    VRFConsumerLite(_idToAddr[requestId]).fulfillRandomWords(
      requestId,
      randomWords
    );
  }
}

