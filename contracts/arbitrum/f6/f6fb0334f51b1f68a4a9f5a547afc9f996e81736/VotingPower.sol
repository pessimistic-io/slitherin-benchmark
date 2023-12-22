// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable2Step.sol";
import "./Pausable.sol";
import "./IStakingRewards.sol";

/// @title Voting power contract for LODE stakers
/// @author Lodestar Finance
/// @notice You can use this contract to vote for emissions to flow to respective token choices in the Lodestar Finance protocol
contract VotingPower is Ownable2Step, Pausable {
    using SafeMath for uint256;

    IStakingRewards public stakingRewards;
    uint256 public votingStartTimestamp;
    uint256 public votingPeriod = 1 weeks;
    uint256 public lodeSpeed = 602739726000000000;
    string[] public enabledTokensList;
    uint256 public lastCountWeek;

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

    event VoteCast(address indexed user, string token, OperationType operation, uint256 shares);
    event DelegateChanged(address indexed user, address indexed newDelegate);
    event NewTokenAdded(string token, bool bothOperationsAllowed);
    event TokenRemoved(string token);
    event NewLodeSpeed(uint256 value);

    constructor(address _stakingRewards, uint256 _votingStartTimestamp) {
        stakingRewards = IStakingRewards(_stakingRewards);
        votingStartTimestamp = _votingStartTimestamp;
    }

    /// @notice Returns the enabled tokens in the protocol.
    /// @return The enabled tokens in the protocol in array form.
    function enabledTokensListView() public view returns (string[] memory) {
        return enabledTokensList;
    }

    /// @notice Update the lode speed constant used in the protocol.
    /// @param value The new lode speed value to update to.
    function updateLodeSpeed(uint256 value) external onlyOwner {        
        lodeSpeed = value;
        emit NewLodeSpeed(lodeSpeed);
    }

    /// @notice Adds new tokens as viable voting options in the protocol.
    /// @param token The string token we wish to add as a voting option.
    /// @param allowBothOperations A boolean representing whether we should allow both operations (true) or just supply (falase).
    function addNewToken(string memory token, bool allowBothOperations) public onlyOwner {
        require(!tokenEnabled[token], "Token already enabled for voting");
        tokenEnabled[token] = true;
        bothOperationsAllowed[token] = allowBothOperations;
        enabledTokensList.push(token);
        emit NewTokenAdded(token, allowBothOperations);
    }

    /// @notice Removes existing tokens as viable voting options in the protocol.
    /// @param _token The string token we wish to remove as a voting option.
    function removeToken(string memory _token) public onlyOwner {
        require(tokenEnabled[_token], "Token not enabled for voting");
        tokenEnabled[_token] = false;

        // Find the index of the token in the enabledTokensList array and remove it.
        for (uint256 i = 0; i < enabledTokensList.length; i++) {
            if (keccak256(abi.encodePacked(enabledTokensList[i])) == keccak256(abi.encodePacked(_token))) {
                enabledTokensList[i] = enabledTokensList[enabledTokensList.length - 1];
                enabledTokensList.pop();
                break;
            }
        }

        emit TokenRemoved(_token);
    }

    /// @notice Delegates existing voting power to an address of the user's choice.
    /// @param to The address in which the user wishes to delegate their voting power to.
    function delegate(address to) external resetVotesIfNeeded whenNotPaused {
        voteDelegates[msg.sender] = to;
        emit DelegateChanged(msg.sender, to);
    }

    /// @notice Returns the current voting week in the protocol.
    /// @return The current week in integer form (week 0 = 0, week 1 = 1, etc.)
    function getCurrentWeek() public view returns (uint256) {
        return (block.timestamp - votingStartTimestamp) / votingPeriod;
    }

    /// @notice A modifier that resets the vote counts for each token and operation at the start of each week.
    /// @dev This modifier first checks if the current week is greater than the last week when the vote counts were reset.
    /// If so, it iterates over the list of enabled tokens and resets the vote counts for both supply and borrow operations.
    /// Finally, it updates the last week when the vote counts were reset to the current week.
    modifier resetVotesIfNeeded() {
        uint256 currentWeek = getCurrentWeek();
        if (currentWeek > lastCountWeek) {
            for (uint256 i = 0; i < enabledTokensList.length; i++) {
                totalVotes[enabledTokensList[i]][OperationType.SUPPLY] = 0;
                totalVotes[enabledTokensList[i]][OperationType.BORROW] = 0;
            }
            lastCountWeek = currentWeek;
        }
        _;
    }

    /// @notice Allows the user to vote towards a specific token/operation combination with their respective voting power.
    /// @param tokens The token the user wishes to vote for (USDC, USDT, ETH, etc).
    /// @param operations The operation, 0 = supply, 1 = borrow, that the user wishes to vote towards.
    /// @param shares The amount of voting power the user can cast via shares.
    function vote(
        string[] calldata tokens,
        OperationType[] calldata operations,
        uint256[] calldata shares
    ) external resetVotesIfNeeded whenNotPaused {
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

    /// @notice Returns the current voting metadata in the protocol.
    /// @return The entire voting status and results, including each token, each operation, and the corresponding vote shares cast for each (represented as a portion of the total lodeSpeed)
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
                    results[i * 2 + j] = votePercentage * lodeSpeed / 1e18; // Multiply by 602739726000000000 and adjust for basis points
                } else {
                    results[i * 2 + j] = 0;
                }
            }
        }
        return (tokens, operations, results);
    }
}

