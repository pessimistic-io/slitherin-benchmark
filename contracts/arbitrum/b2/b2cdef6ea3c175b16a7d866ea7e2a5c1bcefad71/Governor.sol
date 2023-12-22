// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

import "./IGovernor.sol";
import "./Timelock.sol";
import "./IStrategy.sol";
import "./ProxyAdmin.sol";
import "./TransparentUpgradeableProxy.sol";

contract Governor is GovernorBravoDelegateStorageV2, GovernorBravoEvents {
    /// @notice The name of this contract
    string public constant name = " Governor";
    /// @notice The minimum setable voting period
    uint256 public constant MIN_VOTING_PERIOD = 5760; // About 24 hours

    /// @notice The max setable voting period
    uint256 public constant MAX_VOTING_PERIOD = 80640; // About 2 weeks

    /// @notice The maximum number of actions that can be included in a proposal
    uint256 public constant proposalMaxOperations = 10; // 10 actions

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    constructor(
        address strategyReference_,
        address strategy_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 proposalThreshold_,
        uint256 quorumVotes,
        uint256 timelockDelay
    ) {
        require(strategyReference_ != address(0) && strategy_ != address(0), "initialize: invalid address");
        require(
            IStrategy(strategy_).getThreshold(strategyReference_, proposalThreshold_, block.number - 1) > 0,
            "initialize: invalid threshold"
        );

        timelock = TimelockInterface(address(new Timelock(address(this), timelockDelay)));
        strategy = Strategy({
            addr: strategy_,
            referenceAddr: strategyReference_,
            quorumVotes: quorumVotes,
            votingPeriod: votingPeriod_,
            votingDelay: votingDelay_,
            proposalThreshold: proposalThreshold_
        });
        admin = address(timelock);
        emit StrategySet(proposalThreshold_, votingPeriod_, votingDelay_, quorumVotes, strategy_, strategyReference_);
    }

    function setStrategy(Strategy calldata strategy_) external {
        require(msg.sender == address(timelock), "only timelock can set strategy");
        strategy = strategy_;
        emit StrategySet(
            strategy.proposalThreshold,
            strategy.votingPeriod,
            strategy.votingDelay,
            strategy.quorumVotes,
            strategy.addr,
            strategy.referenceAddr
        );
    }

    /**
     * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold
     * @param targets Target addresses for proposal calls
     * @param values Eth values for proposal calls
     * @param signatures Function signatures for proposal calls
     * @param calldatas Calldatas for proposal calls
     * @param description String description of the proposal
     * @return Proposal id of new proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        IStrategy stg = IStrategy(strategy.addr);
        // Allow addresses above proposal threshold and whitelisted addresses to propose
        require(
            stg.getPastVotes(strategy.referenceAddr, msg.sender, block.number - 1) >
                stg.getThreshold(strategy.referenceAddr, strategy.proposalThreshold, block.number - 1) ||
                isWhitelisted(msg.sender),
            "propose: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length,
            "propose: proposal function information arity mismatch"
        );
        require(targets.length != 0, "propose: must provide actions");
        require(targets.length <= proposalMaxOperations, "propose: too many actions");

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(latestProposalId);
            require(
                proposersLatestProposalState != ProposalState.Active,
                "propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "propose: one live proposal per proposer, found an already pending proposal"
            );
        }

        uint256 startBlock = block.number + strategy.votingDelay;
        uint256 endBlock = startBlock + strategy.votingPeriod;

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            eta: 0,
            // targets: targets,
            // values: values,
            // signatures: signatures,
            // calldatas: calldatas,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            canceled: false,
            executed: false,
            strategy: strategy,
            description: description
        });
        _targets[proposalCount] = targets;
        _values[proposalCount] = values;
        _signatures[proposalCount] = signatures;
        _calldatas[proposalCount] = calldatas;
        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            description,
            IStrategy(newProposal.strategy.addr).name()
        );
        return newProposal.id;
    }

    /**
     * @notice Queues a proposal of state succeeded
     * @param proposalId The id of the proposal to queue
     */
    function queue(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "queue: proposal can only be queued if it is succeeded");
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timelock.delay();
        for (uint256 i = 0; i < _targets[proposalId].length; i++) {
            queueOrRevertInternal(
                _targets[proposalId][i],
                _values[proposalId][i],
                _signatures[proposalId][i],
                _calldatas[proposalId][i],
                eta
            );
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function queueOrRevertInternal(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))),
            "queueOrRevertInternal: identical proposal action already queued at eta"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @notice Executes a queued proposal if eta has passed
     * @param proposalId The id of the proposal to execute
     */
    function execute(uint256 proposalId) external payable {
        require(state(proposalId) == ProposalState.Queued, "execute: proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < _targets[proposalId].length; i++) {
            timelock.executeTransaction(
                _targets[proposalId][i],
                _values[proposalId][i],
                _signatures[proposalId][i],
                _calldatas[proposalId][i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
     * @param proposalId The id of the proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        require(state(proposalId) != ProposalState.Executed, "cancel: cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];

        // Proposer can cancel
        if (msg.sender != proposal.proposer) {
            IStrategy stg = IStrategy(proposal.strategy.addr);
            uint256 power = stg.getPastVotes(proposal.strategy.referenceAddr, proposal.proposer, block.number - 1);
            uint256 threshold = stg.getThreshold(
                proposal.strategy.referenceAddr,
                proposal.strategy.proposalThreshold,
                proposal.startBlock
            );
            // Whitelisted proposers can't be canceled for falling below proposal threshold
            if (isWhitelisted(proposal.proposer)) {
                require(power < threshold && msg.sender == whitelistGuardian, "cancel: whitelisted proposer");
            } else {
                require(power < threshold, "cancel: proposer above threshold");
            }
        }

        proposal.canceled = true;
        for (uint256 i = 0; i < _targets[proposalId].length; i++) {
            timelock.cancelTransaction(
                _targets[proposalId][i],
                _values[proposalId][i],
                _signatures[proposalId][i],
                _calldatas[proposalId][i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Gets actions of a proposal
     * @param proposalId the id of the proposal
     * @return targets Targets, values, signatures, and calldatas of the proposal actions
     */
    function getActions(
        uint256 proposalId
    )
        external
        view
        returns (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas)
    {
        return (_targets[proposalId], _values[proposalId], _signatures[proposalId], _calldatas[proposalId]);
    }

    /**
     * @notice Gets the receipt for a voter on a given proposal
     * @param proposalId the id of proposal
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
        return _receipts[keccak256(abi.encodePacked(proposalId, voter))];
    }

    /**
     * @notice Gets the state of a proposal
     * @param proposalId The id of the proposal
     * @return Proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId, "state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        IStrategy stg = IStrategy(proposal.strategy.addr);
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            stg.getThreshold(proposal.strategy.referenceAddr, proposal.strategy.quorumVotes, proposal.startBlock) >
            proposal.forVotes
        ) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @notice Cast a vote for a proposal
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), "");
    }

    /**
     * @notice Cast a vote for a proposal with a reason
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), reason);
    }

    /**
     * @notice Cast a vote for a proposal by signature
     * @dev External function that accepts EIP-712 signatures for voting on proposals.
     */
    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainIdInternal(), address(this))
        );
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "castVoteBySig: invalid signature");
        emit VoteCast(signatory, proposalId, support, castVoteInternal(signatory, proposalId, support), "");
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param voter The voter that is casting their vote
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @return The number of votes cast
     */
    function castVoteInternal(address voter, uint256 proposalId, uint8 support) internal returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "castVoteInternal: voting is closed");
        require(support <= 2, "castVoteInternal: invalid vote type");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = _receipts[keccak256(abi.encodePacked(proposalId, voter))];
        require(receipt.hasVoted == false, "castVoteInternal: voter already voted");
        uint256 votes = IStrategy(proposal.strategy.addr).getPastVotes(
            proposal.strategy.referenceAddr,
            voter,
            proposal.startBlock
        );

        if (support == 0) {
            proposal.againstVotes = proposal.againstVotes + votes;
        } else if (support == 1) {
            proposal.forVotes = proposal.forVotes + votes;
        } else if (support == 2) {
            proposal.abstainVotes = proposal.abstainVotes + votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice View function which returns if an account is whitelisted
     * @param account Account to check white list status of
     * @return If the account is whitelisted
     */
    function isWhitelisted(address account) public view returns (bool) {
        return (whitelistAccountExpirations[account] > block.timestamp);
    }

    /**
     * @notice Admin function for setting the whitelist expiration as a timestamp for an account. Whitelist status allows accounts to propose without meeting threshold
     * @param account Account address to set whitelist expiration for
     * @param expiration Expiration for account whitelist status as timestamp (if now < expiration, whitelisted)
     */
    function _setWhitelistAccountExpiration(address account, uint256 expiration) external {
        require(msg.sender == admin || msg.sender == whitelistGuardian, "_setWhitelistAccountExpiration: admin only");
        whitelistAccountExpirations[account] = expiration;

        emit WhitelistAccountExpirationSet(account, expiration);
    }

    /**
     * @notice Admin function for setting the whitelistGuardian. WhitelistGuardian can cancel proposals from whitelisted addresses
     * @param account Account to set whitelistGuardian to (0x0 to remove whitelistGuardian)
     */
    function _setWhitelistGuardian(address account) external {
        require(msg.sender == admin, "_setWhitelistGuardian: admin only");
        address oldGuardian = whitelistGuardian;
        whitelistGuardian = account;

        emit WhitelistGuardianSet(oldGuardian, whitelistGuardian);
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function _setPendingAdmin(address newPendingAdmin) external {
        // Check caller = admin
        require(msg.sender == admin, "Governor:_setPendingAdmin: admin only");

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function _acceptAdmin() external {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        require(msg.sender == pendingAdmin && msg.sender != address(0), "Governor:_acceptAdmin: pending admin only");

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    function getChainIdInternal() internal view returns (uint256) {
        return block.chainid;
    }
}

