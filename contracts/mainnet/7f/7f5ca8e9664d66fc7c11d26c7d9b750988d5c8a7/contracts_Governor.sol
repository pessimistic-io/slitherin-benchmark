// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./contracts_Governor.sol";
import "./TimelockController.sol";
import "./GovernorCountingSimple.sol";
import "./GovernorSettings.sol";
import "./GovernorVotes.sol";
import "./GovernorVotesQuorumFraction.sol";
import "./GovernorTimelockControl.sol";
import "./ERC20Votes.sol";

import "./Controller.sol";


contract LotteryGovernor is Governor, GovernorSettings, GovernorVotes, GovernorVotesQuorumFraction,
    GovernorCountingSimple, GovernorTimelockControl
{
  constructor(ERC20Votes token, LotteryController controller)
      Governor('EthernaLotto')
      GovernorSettings(
          /*votingDelay=*/6575,
          /*votingPeriod=*/46027,
          /*proposalThreshold=*/1e7 ether)
      GovernorVotes(token)
      GovernorVotesQuorumFraction(6)
      GovernorCountingSimple()
      GovernorTimelockControl(controller) {}

  // The functions below are overrides required by Solidity.

  function _cancel(
      address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
      bytes32 descriptionHash
  )
      internal
      override (Governor, GovernorTimelockControl)
      returns (uint256)
  {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  function _execute(
      uint256 proposalId, address[] memory targets, uint256[] memory values,
      bytes[] memory calldatas, bytes32 descriptionHash
  )
      internal
      override (Governor, GovernorTimelockControl)
  {
    super._execute(proposalId, targets, values, calldatas, descriptionHash);
  }

  function _executor()
      internal
      view
      override (Governor, GovernorTimelockControl)
      returns (address)
  {
    return super._executor();
  }

  function proposalThreshold()
      public
      view
      override (Governor, GovernorSettings)
      returns (uint256)
  {
    return super.proposalThreshold();
  }

  function state(uint256 proposalId)
      public
      view
      override (Governor, GovernorTimelockControl)
      returns (ProposalState)
  {
    return super.state(proposalId);
  }

  function supportsInterface(bytes4 interfaceId)
      public
      view
      override (Governor, GovernorTimelockControl)
      returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}

