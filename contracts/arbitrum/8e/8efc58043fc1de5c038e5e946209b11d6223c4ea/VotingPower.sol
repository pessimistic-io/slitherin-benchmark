// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable2Step.sol";
import "./StakingRewards.sol";

contract VotingPower is Ownable2Step {
    using SafeMath for uint256;

    StakingRewards public stakingRewards;
    uint256 public votingStartTimestamp;
    uint256 public votingPeriod = 1 weeks;

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
    mapping(string => bool) public tokenEnabled;
    mapping(string => bool) public bothOperationsAllowed; 
    mapping(string => mapping(OperationType => uint256)) public totalVotes;
    string[] public enabledTokensList;

    event VoteCast(address indexed user, string token, OperationType operation, uint256 shares);
    event TokenStatusChanged(string token, bool status);
    event DelegateChanged(address indexed user, address indexed newDelegate);
    event NewTokenAdded(string token, bool bothOperationsAllowed);

    constructor(address _stakingRewards, uint256 _votingStartTimestamp) {
        stakingRewards = StakingRewards(_stakingRewards);
        votingStartTimestamp = _votingStartTimestamp;
    }

    function addNewToken(string calldata token, bool allowBothOperations) external onlyOwner {
        require(!tokenEnabled[token], "Token is already enabled for voting");
        
        tokenEnabled[token] = true;
        bothOperationsAllowed[token] = allowBothOperations;
        
        enabledTokensList.push(token);

        emit NewTokenAdded(token, allowBothOperations);
    }

    function delegate(address to) external {
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
            // Will pass if lastVotedWeek[msg.sender] is less than currentWeek (i.e., the user hasn't voted this week) or if currentWeek and lastVotedWeek[msg.sender] are both 0 (i.e., it's the first week since the contract was deployed and the user hasn't voted before).
            lastVotedWeek[msg.sender] < currentWeek || (currentWeek == 0 && lastVotedWeek[msg.sender] == 0),
            "You have already voted this week"
        );

        uint256 userVotingPower = stakingRewards.getAccountTotalSharePercentage(voteDelegates[msg.sender] == address(0) ? msg.sender : voteDelegates[msg.sender]);
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
    }

    function getResults() external view returns (string[] memory, OperationType[] memory, uint256[] memory) {
        string[] memory tokens = new string[](enabledTokensList.length);
        OperationType[] memory operations = new OperationType[](2);
        uint256[] memory results = new uint256[](enabledTokensList.length * 2);

        operations[0] = OperationType.SUPPLY;
        operations[1] = OperationType.BORROW;

        for (uint256 i = 0; i < enabledTokensList.length; i++) {
            tokens[i] = enabledTokensList[i];
        }

        for (uint256 i = 0; i < enabledTokensList.length; i++) {
            for (uint256 j = 0; j < 2; j++) {
                results[i * 2 + j] = totalVotes[tokens[i]][operations[j]];
            }
        }

        return (tokens, operations, results);
    }
}

