// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./interfaces_LinkTokenInterface.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./IInbox.sol";
import "./IOutbox.sol";
import "./IBridge.sol";
import "./verification_Auth.sol";
import "./VRFRequesterL1.sol";

contract RandomnessRelay is Auth, VRFRequesterL1 {
  VRFCoordinatorV2Interface private _coordinator;
  LinkTokenInterface private _linkToken;

  // Rinkeby coordinator. For other networks,
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;

  // Rinkeby LINK token contract. For other networks, see
  // https://docs.chain.link/docs/vrf-contracts/#configurations
  address link_token_contract = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;

  // The gas lane to use, which specifies the maximum gas price to bump to.
  // For a list of available gas lanes on each network,
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  bytes32 _keyHash =
    0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

  // A reasonable default is 100000, but this value could be different
  // on other networks.
  uint32 callbackGasLimit = 100000;

  // The default is 3, but you can set this higher.
  uint16 requestConfirmations = 3;

  // For this example, retrieve 2 random values in one request.
  // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
  uint32 _wordsPerCall = 2;

  // Storage parameters
  uint256[] public s_randomWords;
  uint256 public s_requestId;
  uint64 public subID;
  address _owner;

  address public l2Target;
  IInbox public inbox;

  event RetryableTicketCreated(uint256 indexed ticketId);

  constructor(
    address _l2Target,
    address _inbox,
    Authority authority
  ) Auth(msg.sender, authority) {
    l2Target = _l2Target;
    inbox = IInbox(_inbox);
  }

  function updateL2Target(address _l2Target) public {
    l2Target = _l2Target;
  }

  /// @notice only l2Target can update greeting
  function requestRandomness(uint256 requestId) public override {
    requestId = _coordinator.requestRandomWords(
      _keyHash,
      subID,
      requestConfirmations,
      callbackGasLimit,
      _wordsPerCall
    );
  }
}

