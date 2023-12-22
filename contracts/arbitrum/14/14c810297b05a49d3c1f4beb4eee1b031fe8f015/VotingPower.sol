// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable2Step.sol";
import "./IStakingRewardsTokenV2.sol";

// TODO:
// "is what stops someone flash loaning, buying lode, staking with no lock, voting with all the lode, then selling the lode and paying off flash loan. i dont think current implementation can resist against that"

// I suppose the voting contract could read the txn sender’s stake info struct from the distributor contract
// And check their last stake block
// And if it’s the current block then revert

contract VotingPower is Ownable2Step {
    using SafeMath for uint256;

    IStakingRewardsTokenV2 public stakingRewards;
    uint256 public votingStartTimestamp;
    uint256 public votingPeriod = 1 weeks;
    uint256 public lodeSpeed = 602739726000000000;

    enum OperationType {
        SUPPLY,
        BORROW
    }

    struct Vote {
        uint256 shares;
        string token;
        OperationType operation;
    }

    mapping(address => mapping(uint256 => Vote)) public userVotes;
    mapping(address => address) public voteDelegates; 
    mapping(address => uint256) public lastVotedWeek;
    mapping(address => bool) public previouslyVoted;
    mapping(string => bool) public tokenEnabled;
    mapping(string => bool) public bothOperationsAllowed; 
    mapping(string => mapping(OperationType => uint256)) public totalVotes;
    string[] public enabledTokensList;

    event VoteCast(address indexed user, string token, OperationType operation, uint256 shares);
    event TokenStatusChanged(string token, bool status);
    event DelegateChanged(address indexed user, address indexed newDelegate);
    event NewTokenAdded(string token, bool bothOperationsAllowed);
    event NewLodeSpeed(uint256 value);

    constructor(address _stakingRewards, uint256 _votingStartTimestamp) {
        stakingRewards = IStakingRewardsTokenV2(_stakingRewards);
        votingStartTimestamp = _votingStartTimestamp;
    }

    function updateLodeSpeed(uint256 value) external onlyOwner {        
        lodeSpeed = value;
        emit NewLodeSpeed(lodeSpeed);
    }

    function addNewToken(string calldata token, bool allowBothOperations) external onlyOwner {
        require(!tokenEnabled[token], "Token is already enabled for voting");
        
        tokenEnabled[token] = true;
        bothOperationsAllowed[token] = allowBothOperations;
        
        enabledTokensList.push(token);

        emit NewTokenAdded(token, allowBothOperations);
    }

    function delegate(address to) external {
        require(to != address(0x0000000000000000000000000000000000000000), "Ineligible delegate address");
        voteDelegates[msg.sender] = to;
        emit DelegateChanged(msg.sender, to);
    }

    function getCurrentWeek() public view returns (uint256) {
        return (block.timestamp - votingStartTimestamp) / votingPeriod;
    }

    function vote(
        string[] calldata tokens,
        OperationType[] calldata operations,
        uint256[] calldata shares
    ) external {
        require(
            tokens.length == operations.length && tokens.length == shares.length,
            "Arrays must have the same length"
        );
        
        uint256 currentWeek = getCurrentWeek();
        require(
            // Will pass if lastVotedWeek[msg.sender] is less than currentWeek (i.e., the user hasn't voted this week) or if currentWeek and lastVotedWeek[msg.sender] are both 0
            // (i.e., it's the first week since the contract was deployed and the user hasn't voted before).
            lastVotedWeek[msg.sender] < currentWeek || (currentWeek == 0 && lastVotedWeek[msg.sender] == 0 && !previouslyVoted[msg.sender]),
            "You have already voted this week"
        );

        uint256 userVotingPower = stakingRewards.accountVoteShare(voteDelegates[msg.sender] == address(0) ? msg.sender : voteDelegates[msg.sender]);
        uint256 totalShares = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            string memory token = tokens[i];
            OperationType operation = operations[i];
            uint256 share = shares[i];

            require(share > 0, "Share must be greater than 0");
            require(tokenEnabled[token], "Token is not enabled for voting");
            if (!bothOperationsAllowed[token]) {
                require(operation == OperationType.SUPPLY, "Only supply emissions are allowed for this token");
            }

            userVotes[msg.sender][i] = Vote(share, token, operation);
            totalVotes[token][operation] = totalVotes[token][operation].add(share);
            totalShares = totalShares.add(share);

            emit VoteCast(msg.sender, token, operation, share);
        }

        require(totalShares <= userVotingPower, "Voted shares exceed user's voting power");
        lastVotedWeek[msg.sender] = currentWeek;
        previouslyVoted[msg.sender] = true;
    }

    // TODO:
    // need to take the total lode number quanta returned and 1e18 the result and do some maffs to return the adjusted amount of a specific tokens voting power represented in lode 1e18 stuff
    function getResults() external view returns (string[] memory, OperationType[] memory, uint256[] memory) {
        string[] memory tokens = new string[](enabledTokensList.length);
        OperationType[] memory operations = new OperationType[](2);
        uint256[] memory results = new uint256[](enabledTokensList.length * 2);
        uint256 totalVoteCount = 0;

        operations[0] = OperationType.SUPPLY;
        operations[1] = OperationType.BORROW;

        for (uint256 i = 0; i < enabledTokensList.length; i++) {
            tokens[i] = enabledTokensList[i];
            for (uint256 j = 0; j < 2; j++) {
                totalVoteCount += totalVotes[tokens[i]][operations[j]];
            }
        }

        for (uint256 i = 0; i < enabledTokensList.length; i++) {
            for (uint256 j = 0; j < 2; j++) {
                uint256 voteCount = totalVotes[tokens[i]][operations[j]];
                if (totalVoteCount > 0) {
                    uint256 votePercentage = voteCount * 1e18 / totalVoteCount; // Calculate the vote percentage in basis points
                    results[i * 2 + j] = votePercentage * 602739726000000000 / 1e18; // Multiply by 602739726000000000 and adjust for basis points
                } else {
                    results[i * 2 + j] = 0;
                }
            }
        }

        return (tokens, operations, results);
    }
}
