pragma solidity >=0.8.19;

import "./MerkleProof.sol";

import "./ICommunityDeployer.sol";

import "./CoreDeployment.sol";
import "./DatedIrsDeployment.sol";
import "./PeripheryDeployment.sol";
import "./VammDeployment.sol";

contract CommunityDeployer is ICommunityDeployer {
    /// @notice Timelock Period In Seconds, once the deployment is queued,
    /// 1 day needs to pass in order to make deployment of the Voltz Factory possible
    uint256 public constant TIMELOCK_PERIOD_IN_SECONDS = 1 days;

    /// @notice Multisig owner address
    address public ownerAddress;

    /// @notice The number of votes in support of a proposal required in order for a quorum
    /// to be reached and for a vote to succeed
    uint256 public quorumVotes;

    /// @notice Total number of votes in favour of deploying Voltz Protocol V2 Core
    uint256 public yesVoteCount;

    /// @notice Total number of votes against the deployment of Voltz Protocol V2 Core
    uint256 public noVoteCount;

    /// @notice voting end block timestamp (once this contract is deployed, voting is considered
    /// to be officially started)
    uint256 public blockTimestampVotingEnd;

    /// @notice timelock end block timestamp (once the proposal is queued, the timelock period pre-deployment
    /// is considered to be officially started)
    uint256 public blockTimestampTimelockEnd;

    /// @notice isQueued needs to be true in order for the timelock period to start in advance of the deployment
    bool public isQueued;

    /// @notice isDeployed makes sure contract is deploying at most one Core Proxy
    bool public isDeployed;

    // Merkle Tree
    bytes32 public merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private _votedBitMap;

    /// @notice Voltz V2 Core Proxy to be deployed in a scenario where a successful vote is 
    /// followed by the queue and deployment
    address public coreProxy;

    /// @notice Voltz V2 Account NFT Proxy to be deployed in a scenario where a successful vote is 
    /// followed by the queue and deployment
    address public accountNftProxy;

    /// @notice Voltz V2 Dated IRS Proxy to be deployed in a scenario where a successful vote is 
    /// followed by the queue and deployment
    address public datedIrsProxy;

    /// @notice Voltz V2 Periphery Proxy to be deployed in a scenario where a successful vote is 
    /// followed by the queue and deployment
    address public peripheryProxy;

    /// @notice Voltz V2 VAMM Proxy to be deployed in a scenario where a successful vote is 
    /// followed by the queue and deployment
    address public vammProxy;

    constructor(
        uint256 _quorumVotes,
        address _ownerAddress,
        bytes32 _merkleRoot,
        uint256 _blockTimestampVotingEnd,
        CoreDeployment.Data memory _coreDeploymentConfig,
        DatedIrsDeployment.Data memory _datedIrsDeploymentConfig,
        PeripheryDeployment.Data memory _peripheryDeploymentConfig,
        VammDeployment.Data memory _vammDeploymentConfig
    ) {
        quorumVotes = _quorumVotes;
        ownerAddress = _ownerAddress;
        merkleRoot = _merkleRoot;
        blockTimestampVotingEnd = _blockTimestampVotingEnd;

        CoreDeployment.set(_coreDeploymentConfig);
        DatedIrsDeployment.set(_datedIrsDeploymentConfig);
        PeripheryDeployment.set(_peripheryDeploymentConfig);
        VammDeployment.set(_vammDeploymentConfig);
    }

    function hasVoted(uint256 index) public override view returns (bool) {
        uint256 votedWordIndex = index / 256;
        uint256 votedBitIndex = index % 256;
        uint256 votedWord = _votedBitMap[votedWordIndex];
        uint256 mask = (1 << votedBitIndex);
        return votedWord & mask == mask;
    }

    function _setVoted(uint256 index) private {
        uint256 votedWordIndex = index / 256;
        uint256 votedBitIndex = index % 256;
        _votedBitMap[votedWordIndex] = _votedBitMap[votedWordIndex] | (1 << votedBitIndex);
    }

    /// @notice Deploy the Voltz Factory by passing the masterVAMM and the masterMarginEngine
    /// into the Factory constructor
    function deploy() external override {
        require(isQueued, "not queued");
        require(block.timestamp > blockTimestampTimelockEnd, "timelock is ongoing");
        require(isDeployed == false, "already deployed");

        (coreProxy, accountNftProxy) = CoreDeployment.deploy(ownerAddress);
        datedIrsProxy = DatedIrsDeployment.deploy(ownerAddress);
        peripheryProxy = PeripheryDeployment.deploy(ownerAddress);
        vammProxy = VammDeployment.deploy(ownerAddress);

        isDeployed = true;
    }

    /// @notice Queue the deployment of the Voltz Factory
    function queue() external override {
        require(block.timestamp > blockTimestampVotingEnd, "voting is ongoing");
        require(yesVoteCount >= quorumVotes, "quorum not reached");
        require(yesVoteCount > noVoteCount, "no >= yes");
        require(isQueued == false, "already queued");
        isQueued = true;
        blockTimestampTimelockEnd = block.timestamp + TIMELOCK_PERIOD_IN_SECONDS;
    }

    /// @notice Vote for the proposal to deploy the Voltz Factory contract
    /// @param _index index of the voter
    /// @param _numberOfVotes number of voltz genesis nfts held by the msg.sender before the snapshot was taken
    /// @param _yesVote if this boolean is true then the msg.sender is casting a yes vote,
    /// if the boolean is false the msg.sender is casting a no vote
    /// @param _merkleProof merkle proof that needs to be verified against the merkle root to
    /// check the msg.sender against the snapshot
    function castVote(uint256 _index, uint256 _numberOfVotes, bool _yesVote, bytes32[] calldata _merkleProof)
        external override
    {
        require(block.timestamp <= blockTimestampVotingEnd, "voting period over");

        // check if msg.sender has already voted
        require(!hasVoted(_index), "duplicate vote");

        // verify the merkle proof
        bytes32 _node = keccak256(abi.encodePacked(_index, msg.sender, _numberOfVotes));
        require(MerkleProof.verify(_merkleProof, merkleRoot, _node), "invalid merkle proof");

        // mark hasVoted
        _setVoted(_index);

        // cast the vote
        if (_yesVote) {
            yesVoteCount += _numberOfVotes;
        } else {
            noVoteCount += _numberOfVotes;
        }

        // emit an event
        emit Voted(_index, msg.sender, _numberOfVotes, _yesVote);
    }
}

