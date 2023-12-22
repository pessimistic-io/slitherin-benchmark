//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import "./Governor.sol";
import "./GovernorSettings.sol";
import "./GovernorCountingSimple.sol";
import "./GovernorVotes.sol";
import "./GovernorVotesQuorumFraction.sol";
import "./GovernorTimelockControlConfigurable.sol";
import "./CoraTimelockController.sol";
import "./GovernanceErrors.sol";

/**
 * @title CoraGovernor
 * @notice This contract is used to initiate the Cora governance.
 * @dev This contract is based on the OpenZeppelin Governor contract but implements a
 * GovernorTimelockControlConfigurable.
 */
contract CoraGovernor is
  Governor,
  GovernorSettings,
  GovernorCountingSimple,
  GovernorVotes,
  GovernorVotesQuorumFraction,
  GovernorTimelockControlConfigurable
{
  struct CoraGovernorParams {
    IVotes token;
    CoraTimelockController timelock;
    address messageRelayer;
    bytes4[] functionSignatures;
    DelayType[] functionsDelays;
    uint256 shortDelay;
    uint256 defaultDelay;
    uint256 longDelay;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
  }

  constructor(CoraGovernorParams memory _params)
    Governor("CoraGovernor")
    GovernorSettings(
      _params.initialVotingDelay,
      _params.initialVotingPeriod,
      _params.initialProposalThreshold
    )
    GovernorVotes(_params.token)
    GovernorVotesQuorumFraction(_params.quorumNumeratorValue)
    GovernorTimelockControlConfigurable(
      _params.timelock,
      _params.messageRelayer,
      _params.functionSignatures,
      _params.functionsDelays,
      _params.defaultDelay,
      _params.shortDelay,
      _params.longDelay
    )
  { }

  // The following functions are overrides required by Solidity.
  function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
    return super.votingDelay();
  }

  function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
    return super.votingPeriod();
  }

  function quorum(uint256 blockNumber)
    public
    view
    override(IGovernor, GovernorVotesQuorumFraction)
    returns (uint256)
  {
    return super.quorum(blockNumber);
  }

  function state(uint256 proposalId)
    public
    view
    override(Governor, GovernorTimelockControlConfigurable)
    returns (ProposalState)
  {
    return super.state(proposalId);
  }

  function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) public override(Governor, IGovernor) returns (uint256) {
    if (!_validateProposal(targets, calldatas)) {
      revert DaoInvalidProposal();
    }
    return super.propose(targets, values, calldatas, description);
  }

  function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
    return super.proposalThreshold();
  }

  function quorumDenominator() public view virtual override returns (uint256) {
    return 10000;
  }

  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControlConfigurable) {
    super._execute(proposalId, targets, values, calldatas, descriptionHash);
  }

  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControlConfigurable) returns (uint256) {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  function _executor()
    internal
    view
    override(Governor, GovernorTimelockControlConfigurable)
    returns (address)
  {
    return super._executor();
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(Governor, GovernorTimelockControlConfigurable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}

