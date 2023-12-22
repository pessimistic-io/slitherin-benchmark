//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;
import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable2StepUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./VotesUpgradeable.sol";
import "./VotingConstants.sol";

/// @title Voting power contract for LODE stakers
/// @author Lodestar Finance
/// @notice You can use this contract to vote for emissions to flow to respective token choices in the Lodestar Finance protocol

// TODO: why only works with abstract
contract VotingPower is VotingConstants, Initializable, VotesUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    function initialize(address _stakingRewards, uint256 _votingStartTimestamp) public initializer {
        __Context_init();
        __Ownable2Step_init();
        __Pausable_init();
        __Votes_init();

        stakingRewards = IStakingRewards(_stakingRewards);
        votingStartTimestamp = _votingStartTimestamp;

        //initialize parameters
        DELEGATION_PERIOD = 5 days;
        LODE_SPEED = 602739726000000000;
    }

    /// @notice Returns the enabled tokens in the protocol.
    /// @return The enabled tokens in the protocol in array form.
    function enabledTokensListView() public view returns (string[] memory) {
        return enabledTokensList;
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

    /// @notice Returns the current voting week in the protocol.
    /// @return The current week in integer form (week 0 = 0, week 1 = 1, etc.)
    function getCurrentWeek() public view returns (uint256) {
        return (block.timestamp - votingStartTimestamp) / votingPeriod;
    }

    /// @notice Overriding delegate function to add conditional check if user has voted this week or not
    function delegateVotes(address delegatee) public {
        require(getPeriod() == 1, "VotingPower: Delegation Period has ended");
        // ensure the user is not staked for 10 seconds
        uint256 lockTime = stakingRewards.getStLodeLockTime(msg.sender);
        require(lockTime != 10 seconds, "Lock time cannot be 10 seconds");

        uint256 currentWeek = getCurrentWeek();
        require(
            // Will pass if lastVotedWeek[msg.sender] is less than currentWeek (i.e., the user hasn't voted this week) or if currentWeek and lastVotedWeek[msg.sender] are both 0
            // (i.e., it's the first week since the contract was deployed and the user hasn't voted before).
            lastVotedWeek[msg.sender] < currentWeek ||
                (currentWeek == 0 && lastVotedWeek[msg.sender] == 0 && !previouslyVoted[msg.sender]),
            "You have already voted this week"
        );
        _delegate(msg.sender, delegatee);
    }

    // Increase voting power of a user
    function mint(address _to, uint256 _amount) public {
        // The only contract allowed to call this is stakingRewards
        require(msg.sender == address(stakingRewards), "VotingPower: UNAUTHORIZED");
        _votingPower[_to] += _amount;
        _transferVotingUnits(address(0), _to, _amount); // Adjust voting units
    }

    // Decrease voting power of a user
    function burn(address _from, uint256 _amount) public {
        // The only contract allowed to call this is stakingRewards
        require(msg.sender == address(stakingRewards), "VotingPower: UNAUTHORIZED");
        require(_votingPower[_from] >= _amount, "Burn amount exceeds voting power");
        _votingPower[_from] -= _amount;
        _transferVotingUnits(_from, address(0), _amount); // Adjust voting units
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
        require(getPeriod() == 2, "VotingPower: Voting Period hasn't started yet");

        uint256 currentWeek = getCurrentWeek();
        require(
            // Will pass if lastVotedWeek[msg.sender] is less than currentWeek (i.e., the user hasn't voted this week) or if currentWeek and lastVotedWeek[msg.sender] are both 0
            // (i.e., it's the first week since the contract was deployed and the user hasn't voted before).
            lastVotedWeek[msg.sender] < currentWeek ||
                (currentWeek == 0 && lastVotedWeek[msg.sender] == 0 && !previouslyVoted[msg.sender]),
            "You have already voted this week"
        );

        //get a block number we know has been mined
        uint256 blockNumber = block.number - 1;
        uint256 userVotingPower = getPastVotes(msg.sender, blockNumber);
        uint256 totalShares = 0;

        lastVotedWeek[msg.sender] = currentWeek;
        previouslyVoted[msg.sender] = true;

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
                    uint256 votePercentage = (voteCount * 1e18) / totalVoteCount; // Calculate the vote percentage in basis points
                    results[i * 2 + j] = (votePercentage * LODE_SPEED) / 1e18; // Multiply by 602739726000000000 and adjust for basis points
                } else {
                    results[i * 2 + j] = 0;
                }
            }
        }
        return (tokens, operations, results);
    }

    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return stakingRewards.getStLODEAmount(account);
    }

    function getRawVotingPower(address _user) public view returns (uint256) {
        return _votingPower[_user];
    }

    function getPeriod() public view returns (uint256) {
        uint256 currentWeek = getCurrentWeek();
        uint256 startTime = (currentWeek * 7 days) + votingStartTimestamp;
        uint256 delegationEndTimestamp = startTime + DELEGATION_PERIOD;
        uint256 endTime = startTime + 7 days;
        if (block.timestamp > startTime && block.timestamp <= delegationEndTimestamp) {
            return 1; //this means we are currently in the delegation period
        } else if (block.timestamp > delegationEndTimestamp && block.timestamp < endTime) {
            return 2; //this means we are currently in the voting period
        } else {
            return 0;
        }
    }

    //FUNCTION OVERRIDES

    function delegate(address delegatee) public override {
        delegateVotes(delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        require(block.timestamp <= expiry, "Votes: signature expired");
        require(getPeriod() == 1, "VotingPower: Delegation Period Expired");
        address signer = ECDSAUpgradeable.recover(
            _hashTypedDataV4(keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        require(nonce == _useNonce(signer), "Votes: invalid nonce");
        _delegate(signer, delegatee);
    }

    //ADMIN FUNCTIONS

    /// @notice Update the delegation period constant used in the protocol.
    /// @param newDelegationPeriod The new lode speed value to update to.
    function _updateDelegationPeriod(uint256 newDelegationPeriod) external onlyOwner {
        //delegation period must not be longer than 5 days or shorter than 2 days
        require(
            newDelegationPeriod <= 5 days && newDelegationPeriod >= 2 days,
            "VotingPower: Invalid delegationPeriod"
        );
        uint256 oldDelegationPeriod = DELEGATION_PERIOD;
        DELEGATION_PERIOD = newDelegationPeriod;
        emit DelegationPeriodUpdated(DELEGATION_PERIOD, oldDelegationPeriod, block.timestamp);
    }

    /// @notice Update the lode speed constant used in the protocol.
    /// @param newLodeSpeed The new lode speed value to update to.
    function _updateLodeSpeed(uint256 newLodeSpeed) external onlyOwner {
        uint256 oldLodeSpeed = LODE_SPEED;
        LODE_SPEED = newLodeSpeed;
        emit LodeSpeedUpdated(LODE_SPEED, oldLodeSpeed, block.timestamp);
    }
}

