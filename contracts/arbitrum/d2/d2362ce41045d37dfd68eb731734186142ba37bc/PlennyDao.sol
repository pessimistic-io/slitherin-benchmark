// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;

import "./PlennyBasePausableV2.sol";
import "./PlennyDaoStorage.sol";
import "./SafeMathUpgradeable.sol";

import "./ArbSys.sol";

/// @title  PlennyDao
/// @notice Governs the Dapp via voting on community proposals.
contract PlennyDao is PlennyBasePausableV2, PlennyDaoStorage {

    using SafeMathUpgradeable for uint256;

    /// An event emitted when a new delay is set.
    event NewDelay(uint indexed newDelay);
    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
    /// An event emitted when a new proposal is created.
    event ProposalCreated(uint indexed id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);
    /// An event emitted when a vote has been cast on a proposal.
    event VoteCast(address voter, uint indexed proposalId, bool support, uint votes);
    /// An event emitted when a proposal has been canceled.
    event ProposalCanceled(uint indexed id);
    /// An event emitted when a proposal has been queued in the Timelock.
    event ProposalQueued(uint indexed id, uint eta);
    /// An event emitted when a proposal has been executed in the Timelock.
    event ProposalExecuted(uint indexed id);
    /// An event emitted when a proposal has been canceled.
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    /// An event emitted when a proposal has been executed.
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    /// An event emitted when a proposal has been queued.
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);
    /// An event emitted when a new guardian is set.
    event NewGuardian(address guardian);

    /// @dev    Emits log event of the function calls.
    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /// @dev Checks if a staked balance of a user is above threshold
    modifier onlyGovernanceStakers {
        require(contractRegistry.lockingContract().userPlennyLocked(msg.sender) >= governorThreshold,
            "Not enough staked tokens");
        _;
    }

    /// @notice Initializes the smart contract instead of a constructor.
    /// @dev    Can be called only once during deployment.
    /// @param  _registry PlennyContractRegistry
    function initialize(address _registry) external initializer {
        // sets the minimal quorum to 33.87%
        minQuorum = 3387;
        // set the proposal threshold to 1%
        proposalThreshold = 100;
        // execution delay in blocks count with an average of 13s per block, 2 minutes approximately
        delay = 13000;
        // voting duration & delays in blocks
        votingDuration = 19500;
        votingDelay = 6500;
        governorThreshold = uint256(20000).mul((10 ** uint256(18)));

        PlennyBasePausableV2.__plennyBasePausableInit(_registry);

        guardian = msg.sender;
    }

    /// @notice Submits a governance proposal. The submitter needs to have enough votes at stake in order to submit a proposal
    /// @dev    A proposal is an executable code that consists of the address of the smart contract to call, the function
    ///         (signature to call), and the value(s) provided to that function.
    /// @param  targets addresses of the smart contracts
    /// @param  values values provided to the relevant functions
    /// @param  signatures function signatures
    /// @param  calldatas function data
    /// @param  description the description of the proposal
    /// @return uint proposal id
    function propose(address[] memory targets, uint[] memory values, string[] memory signatures,
        bytes[] memory calldatas, string memory description) external whenNotPaused onlyGovernanceStakers _logs_ returns (uint) {

        uint votes = calculateAvailableVotes(msg.sender, _blockNumber().sub(1));

        require(votes > minProposalVoteCount(_blockNumber().sub(1)), "ERR_BELOW_THRESHOLD");
        require(targets.length == values.length && targets.length == signatures.length
            && targets.length == calldatas.length, "ERR_LENGHT_MISMATCH");
        require(targets.length != 0, "ERR_NO_ACTION");
        require(targets.length <= proposalMaxOperations(), "ERR_MANY_ACTION");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(latestProposalId);
            require(proposersLatestProposalState != ProposalState.Active, "ERR_ALREADY_ACTIVE");
            require(proposersLatestProposalState != ProposalState.Pending, "ERR_ALREADY_PENDING");
        }

        uint startBlock = _blockNumber().add(votingDelay);
        uint endBlock = startBlock.add(votingDuration);

        proposalCount++;
        Proposal memory newProposal = Proposal({
        id : proposalCount,
        proposer : msg.sender,
        eta : 0,
        targets : targets,
        values : values,
        signatures : signatures,
        calldatas : calldatas,
        startBlock : startBlock,
        startBlockAlt: _altBlockNumber(),
        endBlock : endBlock,
        forVotes : 0,
        againstVotes : 0,
        canceled : false,
        executed : false
        });

        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
        return newProposal.id;
    }

    /// @notice Casts a vote for the given proposal.
    /// @param  _proposalID proposal id
    /// @param  support for/against the proposal
    function castVote(uint _proposalID, bool support) external whenNotPaused nonReentrant _logs_ {
        return _castVote(msg.sender, _proposalID, support);
    }

    /// @notice Casts a vote for the given proposal using signed signatures.
    /// @param  _proposalID proposal id
    /// @param  support for/against the proposal
    /// @param  v recover value + 27
    /// @param  r first 32 bytes of the signature
    /// @param  s next 32 bytes of the signature
    function castVoteBySig(uint _proposalID, bool support, uint8 v, bytes32 r, bytes32 s) external whenNotPaused nonReentrant _logs_ {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, _proposalID, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "ERR_INVALID_ADDR");
        return _castVote(signatory, _proposalID, support);
    }

    /// @notice Queues a proposal into the timelock for execution, if it has been voted successfully.
    /// @param  _proposalID proposal id
    function queue(uint _proposalID) external whenNotPaused nonReentrant onlyGovernanceStakers _logs_ {
        require(state(_proposalID) == ProposalState.Succeeded, "ERR_NOT_SUCCESS");
        Proposal storage proposal = proposals[_proposalID];

        uint eta = _blockNumber().add(delay);

        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(_proposalID, eta);
    }

    /// @notice Cancels a proposal.
    /// @param  _proposalID proposal id
    function cancel(uint _proposalID) external whenNotPaused nonReentrant _logs_ {
        ProposalState state = state(_proposalID);
        require(state != ProposalState.Executed, "ERR_ALREADY_EXEC");

        Proposal storage proposal = proposals[_proposalID];

        uint votes = calculateAvailableVotes(proposal.proposer, _blockNumber().sub(1));

        require(msg.sender == guardian || votes < minProposalVoteCount(_blockNumber().sub(1)), "ERR_CANNOT_CANCEL");

        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }

        emit ProposalCanceled(_proposalID);
    }

    /// @notice Executes a proposal that has been previously queued in a timelock.
    /// @param  _proposalID proposal id
    function execute(uint _proposalID) external payable whenNotPaused nonReentrant onlyGovernanceStakers _logs_ {
        require(state(_proposalID) == ProposalState.Queued, "ERR_NOT_QUEUED");

        Proposal storage proposal = proposals[_proposalID];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            executeTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(_proposalID);
    }

    /// @notice Queues proposal to change a guardian. Guardian can temporarily reject unwanted proposals.
    /// @param  newGuardian new guardian address
    /// @param  eta proposal ETA
    function queueSetGuardian(address newGuardian, uint eta) external {
        require(msg.sender == guardian, "ERR_NOT_AUTH");
        queueTransaction(address(this), 0, "setGuardian(address)", abi.encode(newGuardian), eta);
    }

    /// @notice Executes the guardian proposal. Guardian can temporarily reject unwanted proposals.
    /// @param  newGuardian new guardian address
    /// @param  eta proposal ETA for execution
    function executeSetGuardian(address newGuardian, uint eta) external {
        require(msg.sender == guardian, "ERR_NOT_AUTH");
        executeTransaction(address(this), 0, "setGuardian(address)", abi.encode(newGuardian), eta);
    }

    /// @notice Changes the guardian. Only called by the DAO itself.
    /// @param  _guardian new guardian address
    function setGuardian(address _guardian) external {
        require(msg.sender == address(this), "ERR_NOT_AUTH");
        require(_guardian != address(0), "ERR_INVALID_ADDRESS");

        guardian = _guardian;

        emit NewGuardian(_guardian);
    }

    /// @notice Abdicates as a guardian of the DAO.
    function abdicate() external {
        require(msg.sender == guardian, "ERR_NOT_AUTH");
        guardian = address(0);
    }

    /// @notice Changes the proposal delay.
    /// @param  delay_ delay
    function setDelay(uint64 delay_) external onlyOwner _logs_ {
        require(delay_ >= MINIMUM_DELAY, "Delay must exceed minimum delay.");
        require(delay_ <= MAXIMUM_DELAY, "Delay must not exceed maximum delay.");
        delay = delay_;

        emit NewDelay(delay);
    }

    /// @notice Changes the proposal quorum.
    /// @param  value quorum
    function setMinQuorum(uint256 value) external onlyOwner _logs_ {
        minQuorum = value;
    }

    /// @notice Changes the proposal token threshold.
    /// @param  value threshold
    function setProposalThreshold(uint256 value) external onlyOwner _logs_ {
        proposalThreshold = value;
    }

    /// @notice Changes the proposal voting duration.
    /// @param  value voting duration, in blocks
    function setVotingDuration(uint256 value) external onlyOwner _logs_ {
        votingDuration = value;
    }

    /// @notice Changes the proposal voting delay.
    /// @param  value voting delay, in blocks
    function setVotingDelay(uint256 value) external onlyOwner _logs_ {
        votingDelay = value;
    }

    /// @notice Changes the governor threshold. Called by the owner.
	/// @param 	value threshold value of plenny tokens
    function setGovernorThreshold(uint256 value) external onlyOwner _logs_ {
        governorThreshold = value;
    }

    /// @notice Gets the proposal info.
    /// @param  _proposalID proposal id
    /// @return targets addresses of the smart contracts
    /// @return values values provided to the relevant functions
    /// @return signatures function signatures
    /// @return calldatas function data
    function getActions(uint _proposalID) external view returns (address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[_proposalID];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /// @notice Gets the receipt of voting for a proposal.
    /// @param  _proposalID proposal id
    /// @param  voter voter address
    /// @return Receipt receipt info
    function getReceipt(uint _proposalID, address voter) external view returns (Receipt memory) {
        return proposals[_proposalID].receipts[voter];
    }

    /// @notice Min vote quorum at the given block number.
    /// @param  _blockNumber block number
    /// @return _minQuorum The minimum quorum
    function minQuorumVoteCount(uint _blockNumber) public view returns (uint _minQuorum) {
        return contractRegistry.lockingContract().getTotalVoteCountAtBlock(_blockNumber).mul(minQuorum).div(BASE);
    }

    /// @notice Min proposal votes at the given block number.
    /// @param  _blockNumber block number
    /// @return uint votes min votes
    function minProposalVoteCount(uint _blockNumber) public view returns (uint) {
        return contractRegistry.lockingContract().getTotalVoteCountAtBlock(_blockNumber).mul(proposalThreshold).div(BASE);
    }

    /// @notice State of the proposal.
    /// @param  _proposalID proposal id
    /// @return ProposalState The proposal state
    function state(uint _proposalID) public view returns (ProposalState) {
        require(proposalCount >= _proposalID && _proposalID > 0, "ERR_ID_NOT_FOUND");
        Proposal storage proposal = proposals[_proposalID];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (_blockNumber() <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (_blockNumber() <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < minQuorumVoteCount(proposal.startBlock)) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (_blockNumber() >= proposal.eta.add(GRACE_PERIOD)) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /// @notice Maximum number of actions in a proposal.
    /// @return uint number of actions
    function proposalMaxOperations() public pure returns (uint) {
        return 10;
        // 10 actions
    }

    /// @notice Cast a vote for the given proposal.
    /// @param  voter voter address
    /// @param  _proposalID proposal id
    /// @param  support for/against the proposal
    function _castVote(address voter, uint _proposalID, bool support) internal {
        require(state(_proposalID) == ProposalState.Active, "ERR_VOTING_CLOSED");
        Proposal storage proposal = proposals[_proposalID];
        Receipt storage receipt = proposal.receipts[voter];
        require(!receipt.hasVoted, "ERR_DUPLICATE_VOTE");

        uint votes = calculateAvailableVotes(voter, proposal.startBlock);

        require (votes > 0, "ERR_ZERO_VOTES");

        if (support) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, _proposalID, support, votes);
    }

    /// @notice Calculates available votes per user
    /// @return uint256 available votes
    function calculateAvailableVotes(address user, uint256 blockNumber) internal view returns (uint256){
        uint256 availableVotes;
        if (contractRegistry.lockingContract().checkDelegationAtBlock(user, blockNumber)) {
            availableVotes = 
                contractRegistry.lockingContract().getUserDelegatedVoteCountAtBlock(user, blockNumber);
        } else {
            availableVotes = 
                contractRegistry.lockingContract().getUserVoteCountAtBlock(user, blockNumber)
                .add(contractRegistry.lockingContract().getUserDelegatedVoteCountAtBlock(user, blockNumber));
        }
        return availableVotes;
    }    

    /// @notice Alternative block number if on L2.
    /// @return uint256 L1 block number or L2 block number
    function _altBlockNumber() internal view returns (uint256){
        uint chainId = getChainId();
        if (chainId == 42161 || chainId == 421611) {
            return ArbSys(address(100)).arbBlockNumber();
        } else {
            return block.number;
        }
    }

    /// @notice Chain id
    /// @param  chainId The chain id
    function getChainId() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    /// @notice Queues the proposal or reverts if cannot be queued
    /// @param  target address of the smart contracts
    /// @param  value value provided to the relevant function
    /// @param  signature function signature
    /// @param  data function data
    /// @param  eta proposal ETA
    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!queuedTransactions[keccak256(abi.encode(target, value, signature, data, eta))], "ERR_ALREADY_QUEUED");
        queueTransaction(target, value, signature, data, eta);
    }

    /// @notice Queues the proposal
    /// @param  target address of the smart contracts
    /// @param  value value provided to the relevant function
    /// @param  signature function signature
    /// @param  data function data
    /// @param  eta proposal ETA
    /// @return bytes32 transaction hash
    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) internal returns (bytes32) {
        require(eta >= _blockNumber().add(delay), "ERR_ETA_NOT_REACHED");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    /// @notice Cancels the proposal
    /// @param  target address of the smart contracts
    /// @param  value value provided to the relevant function
    /// @param  signature function signature
    /// @param  data function data
    /// @param  eta proposal ETA
    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) internal {

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    /// @notice Executes the proposal
    /// @param  target address of the smart contracts
    /// @param  value value provided to the relevant function
    /// @param  signature function signature
    /// @param  data function data
    /// @param  eta proposal ETA
    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta)
    internal returns (bytes memory) {

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "ERR_NOT_QUEUED");
        require(_blockNumber() >= eta, "ERR_ETA_NOT_REACHED");
        require(_blockNumber() <= eta.add(GRACE_PERIOD), "ERR_STALE_TXN");

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        bool success;
        bytes memory returnData;
        if (target == address(this)) {
            // solhint-disable-next-line avoid-call-value
            (success, returnData) = address(this).call{value : value}(callData);
        } else {
            // solhint-disable-next-line avoid-call-value
            (success, returnData) = target.call{value : value}(callData);
        }

        require(success, "ERR_TXN_REVERTED");

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }
}

