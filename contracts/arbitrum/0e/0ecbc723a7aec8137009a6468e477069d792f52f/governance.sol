// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import "./Initializable.sol";
import "./IChefV2.sol";
import "./ITimelock.sol";
import "./IERC20.sol";

contract GovernorAlpha is Initializable {
    /// @notice The name of this contract
    string public constant name = "ASTRA Governor Alpha";
    
    uint256 public constant MULTIPLIER_DECIMAL = 10000000000000;
    
    uint private quorumVote;
    
    uint private minVoterCount;

    /// @notice The duration of voting on a proposal, in blocks
    uint public votingPeriod ; // ~7 days in blocks (assuming 0.3s blocks time on Arbitrum)
    
    uint public minProposalTimeIntervalSec;
    
    uint public lastProposalTimeIntervalSec;

    uint256 public proposalTokens;

    uint256 public lastProposal;

    uint256 public stakeVault;

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public view returns (uint) { return quorumVote; }

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint) { return 10; } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint) { return 1; } // 1 block
    
    /// @notice Minimum number of voters
    function minVotersCount() external view returns (uint) { return minVoterCount; }

    /// @notice The address of the ASTR Protocol Timelock
    TimelockInterface public timelock;

    /// @notice The address of the ASTR governance token
    IERC20 public ASTR;

    /// @notice The total number of proposals
    uint public proposalCount;

    /// @notice The total number of targets.
    uint256 public totalTarget;
    
    // @notice voter info 
    struct VoterInfo {
        /// @notice Map voter address for proposal
        mapping (address => bool) voterAddress;
        /// @notice Governors votes
        uint voterCount;
        /// @notice Governors votes
        uint256 governors;
    }

    struct Proposal {
        /// @notice ASTRque id for looking up a proposal
        uint id;

        /// @notice Creator of the proposal
        address proposer;

        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint eta;

        /// @notice The name of chain on which the proposal is to be executed 
        string chain;

        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;

        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint[] values;

        /// @notice The ordered list of function signatures to be called
        string[] signatures;

        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;

        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint startBlock;

        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint endBlock;

        /// @notice Current number of votes in favor of this proposal
        uint forVotes;

        /// @notice Current number of votes in opposition to this proposal
        uint againstVotes;

        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;

        /// @notice Flag marking whether the proposal has been executed
        bool executed;

        /// @notice Check is fundamenal changes
        bool fundamentalchanges;

        /// @notice Receipts of ballots for the entire set of voters
        mapping (address => Receipt) receipts;
    }

    /// @notice Track Time proposal is created.
    mapping(uint256 => uint256)public proposalCreatedTime;

    /// @notice Track total proposal user voted on.
    mapping(address => uint256)public propoasalVoted;

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;

        /// @notice Whether or not the voter supports the proposal
        bool support;

        /// @notice The number of votes the voter had, which were cast
        uint votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }
    
    /// @notice Chef Contract address for getting top stakers
    address public chefAddress;

    /// @notice The official record of all voters with id
    mapping (uint => VoterInfo) public votersInfo;

    /// @notice The official record of all proposals ever proposed
    mapping (uint => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping (address => uint) public latestProposalIds;

    mapping (uint256 => bool) public isProposalQueued;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint id, address proposer, string chain, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, bool support, uint votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint id, uint eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint id);

    function initialize(address timelock_, address ASTR_,address _chef) external initializer {
        require(timelock_ != address(0), "Zero Address");
        require(ASTR_ != address(0), "Zero Address");
        require(_chef != address(0), "Zero Address");
        timelock = TimelockInterface(timelock_);
        ASTR = IERC20(ASTR_);
        chefAddress = _chef;
        quorumVote = 40e18;
        minVoterCount = 1;
        minProposalTimeIntervalSec = 1 days;
        proposalTokens = 50_000_000 * 10**18;
        stakeVault = 6 ;
        totalTarget = 3;
        votingPeriod = 2016000;
    }
    /**
     * @notice Update Quorum Value
     * @param _quorumValue New quorum Value.
	 * @dev Update Quorum Votes
     */
    function updateQuorumValue(uint256 _quorumValue) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        quorumVote = _quorumValue; 
    }

    /**
     * @notice Update Voting Period
     * @param _votingPeriod New voting period value.
     * @dev Update voting period value
     */
    function updateVotingPeriod(uint256 _votingPeriod) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        votingPeriod = _votingPeriod; 
    }

    /**
     * @notice Update Stake Vault
     * @param _stakeVault New stake vault value.
	 * @dev Update stake vault value
     */
    function updateStakeVault(uint256 _stakeVault) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        stakeVault = _stakeVault; 
    }

    /**
     * @notice Update Min Voter Value
     * @param _minVotersValue New minimum Votes Value.
	 * @dev Update nummber of minimum voters
     */
    
    function updateMinVotersValue(uint256 _minVotersValue) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        minVoterCount = _minVotersValue; 
    }
    
     /**
     * @notice update Minimum  Proposal Time Interval Sec.
     * @param _minProposalTimeIntervalSec New minimum proposal interval.
	 * @dev Update number of minimum Time for Proposal.
     */
    function updateMinProposalTimeIntervalSec(uint256 _minProposalTimeIntervalSec) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        minProposalTimeIntervalSec = _minProposalTimeIntervalSec; 
    }

     /**
     * @notice update Minimum  Proposal Tokens required.
     * @param _proposalTokens New minimum tokens amount.
	 * @dev Update number of minimum Astra required.
     */

    function updateProposalTokens(uint256 _proposalTokens) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        proposalTokens = _proposalTokens; 
    }
    
    /**
     * @notice Update number of target.
     * @param _totalTarget New maxium target.
	 * @dev Update number of maxium target.
     */

    function updateTotalTarget(uint256 _totalTarget) external {
        require(msg.sender == address(timelock), "Call must come from Timelock.");
        totalTarget = _totalTarget; 
    }

    function _acceptAdmin() external {
        timelock.acceptAdmin();
    }

    /**
     * @notice Create a new Proposal
     * @param chain Chain name for which the proposal is intented.
     * @param targets Target contract whose functions will be called.
     * @param values Amount of ether required for function calling.
     * @param signatures Function that will be called.
     * @param calldatas Paramete that will be passed in function paramt in bytes format.
     * @param description Description about proposal.
     * @param _fundametalChanges Check if proposal involved fundamental changes or not.
	 * @dev Create new proposal. Her only top stakers can create proposal and Need to submit 50000000 Astra tokens to create proposal
     */
    function propose(string memory chain, address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description, bool _fundametalChanges) public returns (uint) {
        // Check if entered configuration is correct or not.
        require(timelock.getL2GovernanceContract(chain) != address(0), "GovernorAlpha::propose: Governance Contract not set for chain");
        require(targets.length <= totalTarget, "GovernorAlpha::propose: Target must be in range");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "GovernorAlpha::propose: proposal function information arity mismatch");
        require(targets.length != 0, "GovernorAlpha::propose: must provide actions");
        require(targets.length <= proposalMaxOperations(), "GovernorAlpha::propose: too many actions");
        // Deposit some Astra tokens to create proposal.
        (bool transferStatus) = depositToken(msg.sender, address(this), proposalTokens);
        stakeToken(msg.sender, proposalTokens);
        // Check transfer status
        require(transferStatus == true, "GovernorAlpha::propose: need to transfer some tokens on contract to create proposal");
        // Check the minimum proposal that can be created in a single day.
        require(add256(lastProposalTimeIntervalSec, sub256(minProposalTimeIntervalSec, mod256(lastProposalTimeIntervalSec, minProposalTimeIntervalSec))) < block.timestamp, "GovernorAlpha::propose: Only one proposal can be create in one day");

        // Check if caller has active proposal or not. If so previous proposal must be accepted or failed first.
        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active, "GovernorAlpha::propose: one live proposal per proposer, found an already active proposal");
          require(proposersLatestProposalState != ProposalState.Pending, "GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal");
        }
        uint256 returnValue = setProposalDetail(chain, targets, values, signatures, calldatas, description, _fundametalChanges);
        return returnValue;
    }

    /**
	 * @dev Internal function for creating proposal parameter details is similar to propose functions.
     */

    function setProposalDetail(string memory chain, address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description, bool _fundametalChanges)internal returns (uint){
        // Set voting time for proposal.
        uint startBlock = add256(block.number, votingDelay());
        uint endBlock = add256(startBlock, votingPeriod);
        proposalCount = add256(proposalCount,1);
        Proposal storage newProposal = proposals[proposalCount];

        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.chain = chain;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;
        newProposal.fundamentalchanges =_fundametalChanges;

        // Update details for proposal.
        proposalCreatedTime[proposalCount] = block.number;

        latestProposalIds[newProposal.proposer] = newProposal.id;
        lastProposalTimeIntervalSec = block.timestamp;
        
        emit ProposalCreated(newProposal.id, msg.sender, chain, targets, values, signatures, calldatas, startBlock, endBlock, description);
        return newProposal.id;
    }

    /**
     * @notice Deposit Astra tokens.
     * @param sender Sender Address
     * @param recipient Reciever Address
     * @param amount Amount to spent
	 * @dev Deposit Astra token at time new proposal
     */

    function depositToken(address sender, address recipient, uint256 amount) internal returns(bool) {
        bool transferStatus = ASTR.transferFrom(sender, recipient, amount);
        return transferStatus;
    }
    /**
     * @notice Stake Astra tokens.
     * @param sender Sender Address
     * @param amount Amount to spent
	 * @dev Stake Astra token at time new proposal
     */

    function stakeToken(address sender, uint256 amount) internal {
        ASTR.approve(address(chefAddress),amount);
        ChefInterface(chefAddress).depositWithUserAddress(amount,stakeVault,sender);
    }


    /**
     * @notice Queue your proposal.
     * @param proposalId Proposal Id.
	 * @dev Once proposal is accepted put them in queue over timelock. Proposal can only be put in queue if it is succeeded and crossed minimum voter.
     */

    function queue(uint proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "GovernorAlpha::queue: proposal can only be queued if it is succeeded");
        require(votersInfo[proposalId].voterCount >= minVoterCount, "GovernorAlpha::queue: proposal require atleast min governers quorum");
        Proposal storage proposal = proposals[proposalId];
        uint eta = add256(block.timestamp, timelock.delay()); 
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.chain, proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        isProposalQueued[proposalId] = true;
        emit ProposalQueued(proposalId, eta);
    }

     /**
	 * @dev Internal function called by queue to check if proposal can be queued or not.
     */

    function _queueOrRevert(string memory chain, address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(chain, target, value, signature, data, eta))), "GovernorAlpha::_queueOrRevert: proposal action already queued at eta");
        timelock.queueTransaction(chain, target, value, signature, data, eta);
    }

    /**
     * @notice Execute your proposal.
     * @param proposalId Proposal Id.
	 * @dev Once queue time is over you can execute proposal fucntion from here.
     */

    function execute(uint256 proposalId) external payable {
        require(state(proposalId) == ProposalState.Queued, "GovernorAlpha::execute: proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value : proposal.values[i]}(proposal.chain, proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        lastProposal = proposalId;
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel your proposal.
     * @param proposalId Proposal Id.
	 * @dev If proposal is not executed you can cancel that proposal from here.
     */

    function cancel(uint proposalId) external {
        ProposalState _state = state(proposalId);
        require(_state != ProposalState.Executed, "GovernorAlpha::cancel: cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];

        require(msg.sender == proposal.proposer, "GovernorAlpha::cancel: Only creator can cancel");

        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(proposal.chain, proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Get Actions details
     * @param proposalId Proposal Id.
	 * @dev Get the details of Functions that will be called.
     */

    function getActions(uint proposalId) external view returns (string memory chain, address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.chain, p.targets, p.values, p.signatures, p.calldatas);
    }

        /**
     * @notice Get Receipt
     * @param proposalId Proposal Id.
     * @param voter Voter address
	 * @dev Get the details of voted on a particular proposal for a user.
     */

    function getReceipt(uint proposalId, address voter) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    function getVotingStatus(address _voter) external view returns(bool) {
        return (propoasalVoted[_voter] == proposalCount);
    }
    /**
     * @notice Get state of proposal
     * @param proposalId Proposal Id.
	 * @dev Check the status of proposal
     */

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "GovernorAlpha::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        // Check min governor vote required. Each proposal require some minimum proposal based on its type.
        // For testnet and testing these values are set to lower.
        bool checkifMinGovenor;
        bool checkFastVote = checkfastvote(proposalId);
        uint256 percentage = 10;
        // Check if proposal is fundamental or not. For both different requirment is set.
        // This is used to check if proposal passed minimum governor barrier.
        if(proposal.fundamentalchanges){
            percentage = 20;
            if(votersInfo[proposalId].governors>=51){
                checkifMinGovenor = true;
            }else{
                checkifMinGovenor = false;
            }
        }else{
            if(votersInfo[proposalId].governors>=33){
                checkifMinGovenor = true;
            }else{
                checkifMinGovenor = false;
            }
        }
        // Check if proposal is fast vote or not. Only for non fundamental proposal.
        if(checkFastVote && checkifMinGovenor && !isProposalQueued[proposalId]){
            return ProposalState.Succeeded;
        }
        else if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock && proposal.eta == 0) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock && proposal.eta == 0) {
            return ProposalState.Active;
        } else if ((proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) && proposal.eta == 0) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            // Check if proposal matched all the conditions for acceptance.
            if(checkifMinGovenor){
                    if(proposal.againstVotes==0){
                        return ProposalState.Succeeded;
                    }else{
                    uint256 voteper=  div256(mul256(sub256(proposal.forVotes, proposal.againstVotes),100), proposal.againstVotes);
                     if(voteper>percentage){
                        return ProposalState.Succeeded;
                    }
                    }
            }
            return ProposalState.Defeated;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

     /**
     * @notice Get fast vote state of proposal
     * @param proposalId Proposal Id.
	 * @dev Check the fast vote status of proposal
     */

    function checkfastvote(uint proposalId) public view returns (bool){
        require(proposalCount >= proposalId && proposalId > 0, "GovernorAlpha::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        uint256 oneday = add256(proposalCreatedTime[proposalId],6500);
        uint256 percentage = 10;
        bool returnValue;
        // Check if proposal is non fundamental and block number is less than for 1 day since the proposal created.
        if(proposal.fundamentalchanges==false && block.number <= oneday){
            // Check if all conditions are matched or not.
            if (block.number <= proposal.endBlock && proposal.againstVotes <= proposal.forVotes && proposal.forVotes >= quorumVotes()) {
                    // uint256 voteper= proposal.forVotes.sub(proposal.againstVotes).mul(100).div(proposal.againstVotes);
                    if(proposal.againstVotes==0){
                        returnValue = true;
                    }else{
                        uint256 voteper=  div256(mul256(sub256(proposal.forVotes, proposal.againstVotes),100), proposal.againstVotes);
                    if(voteper>percentage){
                        returnValue = true;
                    }
                    }
            }
        }
        return returnValue;
    }

     /**
     * @notice Vote on any proposal
     * @param proposalId Proposal Id.
     * @param support Bool value for your vote
	 * @dev Vote on any proposal true for acceptance and false for defeat.
     */

    function castVote(uint proposalId, bool support) external {
        _castVote(msg.sender, proposalId, support);
    }

    /**
     * @notice Vote on any proposal
     * @param proposalId Proposal Id.
     * @param support Bool value for your vote
     * @param v Used for signature
     * @param r Used for signature
     * @param s Used for signature
	 * @dev Vote on any proposal true for acceptance and false for defeat. Here you will vote by signature
     */

    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "GovernorAlpha::castVoteBySig: invalid signature");
        _castVote(signatory, proposalId, support);
    }
    /**
    * @dev Cast vote internal function.
    */

    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        bool isTopStaker = ChefInterface(chefAddress).checkHighestStaker(voter);
        if(!votersInfo[proposalId].voterAddress[voter])
        {
          votersInfo[proposalId].voterAddress[voter] = true;
          votersInfo[proposalId].voterCount = add256(votersInfo[proposalId].voterCount,1);
          if(isTopStaker){
              votersInfo[proposalId].governors = add256(votersInfo[proposalId].governors,1);
          }
        }
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "GovernorAlpha::_castVote: voter already voted");
        // uint256 votes = ASTR.getPriorVotes(voter, proposal.startBlock);
        uint256 votes = userVoteCount(0, voter);
        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }
        propoasalVoted[voter] = add256(propoasalVoted[voter],1);
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    function userVoteCount(
        uint256 _pid,
        address _userAddress
    )
        internal
        view
        returns (
            uint256
        )
    {
        uint256 _amount;
        uint256 _stakingScore;
        uint256 _currentMultiplier;
        uint256 _maxMultiplier;
        (_amount,,,,,,) = ChefInterface(chefAddress).userInfo(_pid,_userAddress);
        (_stakingScore, _currentMultiplier, _maxMultiplier) = ChefInterface(chefAddress).stakingScoreAndMultiplier(_userAddress,_amount);
        return div256(mul256(_stakingScore,_currentMultiplier), MULTIPLIER_DECIMAL);
    }

   /**
    * @dev Functions used for internal safemath purpose.
    */
    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }
    
    function mod256(uint a, uint b) internal pure returns (uint) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
    function mul256(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div256(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    } 
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }


    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}


