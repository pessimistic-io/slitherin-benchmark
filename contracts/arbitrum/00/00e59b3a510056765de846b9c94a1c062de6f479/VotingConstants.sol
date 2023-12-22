// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IStakingRewards.sol";

contract VotingConstants {
    IStakingRewards public stakingRewards;
    uint256 public votingStartTimestamp;
    string[] public enabledTokensList;
    uint256 public lastCountWeek;
    uint256 public constant votingPeriod = 1 weeks;
    uint256 public DELEGATION_PERIOD;
    uint256 public LODE_SPEED;
    bytes32 constant _DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    enum OperationType {
        SUPPLY,
        BORROW
    }

    struct Vote {
        uint256 shares;
        string token;
        OperationType operation;
    }

    mapping(address => uint256) public _votingPower;
    mapping(address => mapping(uint256 => Vote)) public userVotes;
    mapping(address => uint256) public lastVotedWeek;
    mapping(address => bool) public previouslyVoted;
    mapping(string => bool) public tokenEnabled;
    mapping(string => bool) public bothOperationsAllowed;
    mapping(string => mapping(OperationType => uint256)) public totalVotes;

    event VoteCast(address indexed user, string token, OperationType operation, uint256 shares);
    event NewTokenAdded(string token, bool bothOperationsAllowed);
    event TokenRemoved(string token);
    event VotesCleared(address indexed account, string token, OperationType operation, uint256 remainingShares);
    event DelegationPeriodUpdated(uint256 newDelegationPeriod, uint256 oldDelegationPeriod, uint256 updateTimestamp);
    event LodeSpeedUpdated(uint256 newLodeSpeed, uint256 oldLodeSpeed, uint256 updateTimestamp);
    event StakingRewardsUpdated(IStakingRewards newStakingRewards, uint256 updateTimestamp);
    //STOP. ANY ADDITIONAL STORAGE VARIABLES SHOULD BE INITIALIZED IN A SEPARATE CONTRACT BELOW, IE VOTINGCONSTANTSV2 WHICH INHERITS THE PREVIOUS ONES TO MAINTAIN THE SAME STORAGE LAYOUT.
}

