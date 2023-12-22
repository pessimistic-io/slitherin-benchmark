// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./IPlennyERC20.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyStakeGovDelVStorage.sol";
import "./IPlennyLocking.sol";
import "./ExtendedMathLib.sol";

/// @title PlennyStakeGovDelV
/// (PlennyLocking in BETA release.)
/// @notice Manages staking for governance and the delegation of voting rights.
///         Attn: The storage contract refers to governance staking (not locking).
contract PlennyStakeGovDelV is PlennyBasePausableV2, PlennyStakeGovDelVStorage {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IPlennyERC20;
    using ExtendedMathLib for uint256;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @dev    logs the function calls.
    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /// @notice Initializes the contract. Called once during deployment.
    /// @param  _registry plenny contract registry
    function initialize(address _registry) external initializer {
        // 5%
        lockingFee = 500;

        // 0.5%
        exitFee = 50;

        // 1 day = 6500 blocks
        nextDistributionBlocks = 6500;

        // 1 week in blocks
        averageBlocksPerWeek = 45500;

        // 0.01%
        govLockReward = 1;

        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Locks Plenny in the governance.
    /// @param  amount plenny amount
    /// @param  period period, in weeks
    function lockPlenny(uint256 amount, uint period) external whenNotPaused nonReentrant _logs_ {
        _plennyLocked(msg.sender, amount, period);
    }

    /// @notice Relocks Plenny after the locking period expires.
    /// @param  index id of the previously locked record
    /// @param  period the new locking period, in weeks
    function relockPlenny(uint256 index, uint period) external whenNotPaused nonReentrant _logs_ {
        uint256 i = recordIndexesPerAddress[msg.sender][index];
        require(i < lockedRecords.length, "ERR_NOT_FOUND");
        require(period != 0, "ERR_INVALID_PERIOD");
        LockedRecord storage record = lockedRecords[i];
        require(record.owner == msg.sender, "ERR_NO_PERMISSION");
        require(record.endDate < _blockNumber(), "ERR_LOCKED");

        uint oldVote = record.amount.mul(record.multiplier).div(WEIGHT_MULTIPLIER);

        userVoteCount[msg.sender] = userVoteCount[msg.sender].sub(oldVote);
        totalVotesLocked = totalVotesLocked.sub(oldVote);

        uint256 multiplier = calculateMultiplier(period);
        record.endDate = _blockNumber().add(averageBlocksPerWeek.mul(period));
        record.multiplier = multiplier;

        uint newVote = record.amount.mul(record.multiplier).div(WEIGHT_MULTIPLIER);

        userVoteCount[msg.sender] = userVoteCount[msg.sender].add(newVote);
        totalVotesLocked = totalVotesLocked.add(newVote);

        if (hasDelegated[msg.sender]) {
            uint256 addDelegatedVote = newVote > oldVote? newVote - oldVote : oldVote - newVote;
            userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor] = 
                userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor].add(addDelegatedVote);
            bool newVsOld = newVote > oldVote? true : false;
            _voteChanged(myDelegatedGovernor[msg.sender].governor, 0, addDelegatedVote, 
                hasDelegated[myDelegatedGovernor[msg.sender].governor], newVsOld);
        }

        if (newVote > oldVote) {
            _voteChanged(msg.sender, newVote - oldVote, 0, hasDelegated[msg.sender], true);
        } else {
            _voteChanged(msg.sender, oldVote - newVote, 0, hasDelegated[msg.sender], false);
        }
    }

    /// @notice Withdraws the Plenny tokens, once the locking period has expired.
    /// @param  index id of the locking record
    function withdrawPlenny(uint256 index) external whenNotPaused nonReentrant _logs_ {
        uint256 i = recordIndexesPerAddress[msg.sender][index];
        require(i < lockedRecords.length, "ERR_NOT_FOUND");

        LockedRecord storage record = lockedRecords[i];
        require(record.owner == msg.sender, "ERR_NO_PERMISSION");
        require(record.endDate < _blockNumber(), "ERR_LOCKED");

        if (recordIndexesPerAddress[msg.sender].length == 1) {
            userLockedPeriod[msg.sender] = 0;
        }

        uint256 fee = record.amount.mul(exitFee).div(100).div(100);
        uint256 vote = record.amount.mul(record.multiplier).div(WEIGHT_MULTIPLIER);

        if (_blockNumber() > userLastCollectedPeriod[msg.sender].add(nextDistributionBlocks)) {
            totalUserEarned[msg.sender] = totalUserEarned[msg.sender].add(
                calculateReward(vote).mul(_blockNumber().sub(userLastCollectedPeriod[msg.sender])).div(nextDistributionBlocks));
            totalVotesCollected = totalVotesCollected.add(vote);
            totalVotesLocked = totalVotesLocked.sub(vote);
        } else {
            totalVotesLocked = totalVotesLocked.sub(vote);
        }

        userValueLocked[msg.sender] = userValueLocked[msg.sender].sub(record.amount);
        userVoteCount[msg.sender] = userVoteCount[msg.sender].sub(vote);
        totalValueLocked = totalValueLocked.sub(record.amount);

        record.deleted = true;
        removeElementFromArray(index, recordIndexesPerAddress[msg.sender]);
        _voteChanged(msg.sender, vote, 0, hasDelegated[msg.sender], false);

        if (hasDelegated[msg.sender]) {
            userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor] = 
                userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor].sub(vote);
            _voteChanged(myDelegatedGovernor[msg.sender].governor, 0, vote, 
                hasDelegated[myDelegatedGovernor[msg.sender].governor], false);
        }

        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        token.safeTransfer(msg.sender, record.amount - fee);
        token.safeTransfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), fee);
    }

    /// @notice Collects Plenny reward for the locked Plenny tokens.
    function collectReward() external whenNotPaused nonReentrant {
        if (totalUserEarned[msg.sender] == 0) {
            require(userLockedPeriod[msg.sender] < _blockNumber(), "ERR_LOCKED_PERIOD");
        }

        uint256 multiplier = (_blockNumber().sub(userLastCollectedPeriod[msg.sender])).div(nextDistributionBlocks);
        uint256 reward = calculateReward(userVoteCount[msg.sender]).mul(multiplier).add(totalUserEarned[msg.sender]);
        uint256 fee = reward.mul(lockingFee).div(10000);

        bool reset = true;
        uint256 [] memory userRecords = recordIndexesPerAddress[msg.sender];
        for (uint256 i = 0; i < userRecords.length; i++) {
            LockedRecord storage record = lockedRecords[userRecords[i]];
            reset = false;
            if (record.multiplier > WEIGHT_MULTIPLIER && record.endDate < _blockNumber()) {
                uint256 diff = record.amount.mul(record.multiplier).div(WEIGHT_MULTIPLIER).sub(record.amount);
                userVoteCount[msg.sender] = userVoteCount[msg.sender].sub(diff);
                totalVotesLocked = totalVotesLocked.sub(diff);
                record.multiplier = uint256(1).mul(WEIGHT_MULTIPLIER);
            }
        }

        if (reset) {
            userLockedPeriod[msg.sender] = 0;
        } else {
            userLockedPeriod[msg.sender] = _blockNumber().add(nextDistributionBlocks);
        }
        userLastCollectedPeriod[msg.sender] = _blockNumber();
        totalUserEarned[msg.sender] = 0;
        totalVotesCollected = 0;

        IPlennyReward plennyReward = contractRegistry.rewardContract();
        require(plennyReward.transfer(msg.sender, reward - fee), "Failed");
        require(plennyReward.transfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), fee), "Failed");
    }

    /// @notice Delegates Plenny to the given governor.
    /// @param  newGovernor address of the governor to delegate to
    function delegateTo(address payable newGovernor) external whenNotPaused _logs_ {
        require(myDelegatedGovernor[msg.sender].governor != newGovernor, "ERR_ALREADY_DELEGATION");
        require(msg.sender != newGovernor, "ERR_SELF_DELEGATION");
        require(userVoteCount[newGovernor] > 0, "ERR_NOT_GOVERNOR");
        myDelegatedGovernor[msg.sender].delegationIndex = myDelegatedGovernor[msg.sender].delegationIndex.add(1);
        myDelegatedGovernor[msg.sender].governor = newGovernor;

        userDelegatedVotesCount[newGovernor] = userDelegatedVotesCount[newGovernor].add(userVoteCount[msg.sender]);
        hasDelegated[msg.sender] = true;
        _voteChanged(msg.sender, 0, 0, hasDelegated[msg.sender], false);
        _voteChanged(newGovernor, 0, userVoteCount[msg.sender], hasDelegated[newGovernor], true);
    }

    /// @notice Removes a delegation.
    function undelegate() public whenNotPaused _logs_ {
        require(myDelegatedGovernor[msg.sender].delegationIndex > 0, "ERR_NOT_DELEGATING");
        userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor] = 
            userDelegatedVotesCount[myDelegatedGovernor[msg.sender].governor].sub(userVoteCount[msg.sender]);

        myDelegatedGovernor[msg.sender].delegationIndex = 0;
        _voteChanged(msg.sender, 0, 0, false, true);
        _voteChanged(myDelegatedGovernor[msg.sender].governor, 0, userVoteCount[msg.sender], 
            hasDelegated[myDelegatedGovernor[msg.sender].governor], false);

        delete myDelegatedGovernor[msg.sender];
        hasDelegated[msg.sender] = false;
    }

    /// @notice Changes the next distribution in seconds. Managed by the contract owner
    /// @param  amount number of blocks.
    function setNextDistributionBlocks(uint256 amount) external onlyOwner {
        nextDistributionBlocks = amount;
    }

    /// @notice Changes the governance lock reward multiplier. Managed by the contract owner.
    /// @param  amount multiplier of 100
    function setGovLockReward(uint256 amount) external onlyOwner {
        govLockReward = amount;
    }

    /// @notice Changes the exit Fee. Managed by the contract owner.
    /// @param  amount multiplier of 100
    function setGovExitFee(uint256 amount) external onlyOwner {
        exitFee = amount;
    }

    /// @notice Changes the locking Fee multiplier. Managed by the contract owner.
    /// @param  amount multiplier of 100
    function setLockingFee(uint256 amount) external onlyOwner {
        lockingFee = amount;
    }

    /// @notice Changes average block counts per week. Managed by the contract owner.
    /// @param  count blocks per week
    function setAverageBlocksPerWeek(uint256 count) external onlyOwner {
        averageBlocksPerWeek = count;
    }

    /// @notice Gets number of locked records per address.
    /// @param  addr address to check
    /// @return uint256 number
    function getRecordIndexesPerAddressCount(address addr) external view returns (uint256){
        return recordIndexesPerAddress[addr].length;
    }

    /// @notice Gets locked records per address.
    /// @param  addr address to check
    /// @return uint256[] arrays of indexes
	function getRecordIndexesPerAddress(address addr) external view returns (uint256[] memory){
		return recordIndexesPerAddress[addr];
	}

    /// @notice Number of total locked records.
    /// @return uint256 number of records
    function lockedBalanceCount() external view returns (uint256) {
        return lockedRecords.length;
    }

    /// @notice Shows potential reward for the given user.
    /// @return uint256 token amount
    function getPotentialRewardGov() external view returns (uint256) {
        return calculateReward(userVoteCount[msg.sender]);
    }

    /// @notice Gets the total votes from all users at the given block number.
    /// @param  blockNumber block number
    /// @return uint256 total votes
    function getTotalVoteCountAtBlock(uint blockNumber) external view override returns (uint256) {
        (uint256 voteCount, , ) = 
            _iterateCheckpoints(blockNumber, totalVoteNumCheckpoints, totalVoteCount);
        return voteCount;
    }

    /// @notice Gets the votes for the given user at the given block number.
    /// @param  account user address
    /// @param  blockNumber block number
    /// @return uint256 vote per user
    function getUserVoteCountAtBlock(address account, uint blockNumber) external view override returns (uint256) {
        (uint256 voteCount, , ) = 
            _iterateCheckpoints(blockNumber, numCheckpoints[account], checkpoints[account]);
        return voteCount;
    }

    /// @notice Gets the delegated votes for the given user at the given block number.
    /// @param  account user address
    /// @param  blockNumber block number
    /// @return uint256 delegated votes per user
    function getUserDelegatedVoteCountAtBlock(address account, uint blockNumber) external view override returns (uint256) {
        (, uint256 delegatedVotes, ) = 
            _iterateCheckpoints(blockNumber, numCheckpoints[account], checkpoints[account]);
        return delegatedVotes;
    }

    /// @notice Checks if a governor has delegated to other governor at the given block number.
    /// @param  governor address to check
    /// @param  blockNumber block number
    /// @return bool true/false
    function checkDelegationAtBlock(address governor, uint blockNumber) external view override returns (bool) {
        (, , bool isDelegating ) = 
            _iterateCheckpoints(blockNumber, numCheckpoints[governor], checkpoints[governor]);
        return isDelegating;
    }

    /// @notice Calculates the reward of the user based on the user's participation (votes) in the the locking.
    /// @param  votes participation in the locking
    /// @return uint256 plenny reward amount
    function calculateReward(uint256 votes) public view returns (uint256) {
        if (totalVotesLocked > 0) {

            return contractRegistry.plennyTokenContract().balanceOf(
                contractRegistry.requireAndGetAddress("PlennyReward")).mul(
                govLockReward).mul(votes).div(totalVotesLocked.add(totalVotesCollected)).div(10000);
        } else {
            return 0;
        }
    }

    /// @notice Contains logic for the locking of Plenny for the given beneficiary account.
    /// @param  beneficiary address
    /// @param  amount locking amount
    /// @param  period period, in weeks
    function _plennyLocked(address beneficiary, uint256 amount, uint period) internal {
        require(amount > 0, "ERR_EMPTY");
        require(msg.sender == beneficiary, "ERR_NOT_AUTH");

        uint256 multiplier = calculateMultiplier(period);
        uint256 endDate = _blockNumber().add(averageBlocksPerWeek.mul(period));
        lockedRecords.push(LockedRecord(beneficiary, amount, _blockNumber(), endDate, multiplier, false));
        uint256 index = lockedRecords.length - 1;
        recordIndexesPerAddress[beneficiary].push(index);

        uint vote = amount.mul(multiplier).div(WEIGHT_MULTIPLIER);

        userValueLocked[beneficiary] = userValueLocked[beneficiary].add(amount);
        userVoteCount[beneficiary] = userVoteCount[beneficiary].add(vote);
        totalVotesLocked = totalVotesLocked.add(vote);
        totalValueLocked = totalValueLocked.add(amount);
        if (userLockedPeriod[beneficiary] == 0) {
            userLockedPeriod[beneficiary] = _blockNumber().add(nextDistributionBlocks);
            userLastCollectedPeriod[beneficiary] = _blockNumber();
        }

        userDelegatedVotesCount[myDelegatedGovernor[beneficiary].governor] = 
            userDelegatedVotesCount[myDelegatedGovernor[beneficiary].governor].add(vote);

        _voteChanged(beneficiary, vote, 0, hasDelegated[beneficiary], true);

        if (hasDelegated[beneficiary]) {
            _voteChanged(myDelegatedGovernor[beneficiary].governor, 0, vote, hasDelegated[myDelegatedGovernor[beneficiary].governor], true);
        }

        contractRegistry.plennyTokenContract().safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Triggered whenever the user's locking amount has changed.
    /// @param  user address
    /// @param  amount delta amount
    /// @param  increase true, if amount is increasing, false otherwise
    function _voteChanged(address user, uint amount, uint delegatedAmount, bool delegated, bool increase) internal {
        uint chkNum = numCheckpoints[user];
        uint oldVotes = chkNum > 0 ? checkpoints[user][chkNum - 1].voteCount : 0;
        uint oldDelegatedVotes = chkNum > 0 ? checkpoints[user][chkNum - 1].delegatedVoteCount : 0;
        // get latest checkpoint votes
        uint newVotes = increase ? oldVotes.add(amount) : oldVotes.sub(amount);
        uint newDelegatedVotes = increase ? oldDelegatedVotes.add(delegatedAmount) : oldDelegatedVotes.sub(delegatedAmount);

        // write checkpoint for totalVoteCount
        uint oldTotalVotes = totalVoteNumCheckpoints > 0 ? totalVoteCount[totalVoteNumCheckpoints - 1].voteCount : 0;
        uint oldDelegatedTotalVotes = totalVoteNumCheckpoints > 0 ? 
            totalVoteCount[totalVoteNumCheckpoints - 1].delegatedVoteCount : 0;

        // get latest checkpoint votes
        uint newTotalVotes = increase ? oldTotalVotes.add(amount) : oldTotalVotes.sub(amount);
        uint newDelegatedTotalVotes = increase ? oldDelegatedTotalVotes.add(delegatedAmount) : oldDelegatedTotalVotes.sub(delegatedAmount);

        _writeNewCheckpoint(user, chkNum, newVotes, newDelegatedVotes, delegated);
        _writeNewTotalVoteCheckpoint(totalVoteNumCheckpoints, newTotalVotes, newDelegatedTotalVotes, delegated);
    }

    /// @notice Stores new checkpoint for the user.
    /// @param  user address
    /// @param  nCheckpoints number of checkpoints
    /// @param  newVotes new votes
    function _writeNewCheckpoint(address user, uint nCheckpoints, uint newVotes, uint newDelegatedVotes, bool delegated) internal {
        uint blockNumber = _blockNumber();

        if (nCheckpoints > 0 && checkpoints[user][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[user][nCheckpoints - 1].voteCount = newVotes;
            checkpoints[user][nCheckpoints - 1].delegatedVoteCount = newDelegatedVotes;
            checkpoints[user][nCheckpoints - 1].isDelegating = delegated;
        } else {
            checkpoints[user][nCheckpoints] = Checkpoint(blockNumber, newVotes, newDelegatedVotes, delegated);
            numCheckpoints[user] = nCheckpoints + 1;
        }
    }

    /// @notice Store new total checkpoint for all users.
    /// @param  nTotalCheckpoints number of total checkpoints
    /// @param  newTotalVotes total votes
    function _writeNewTotalVoteCheckpoint(uint nTotalCheckpoints, uint newTotalVotes, 
        uint newTotalDelegatedVotes, bool delegated) internal {
        uint blockNumber = _blockNumber();

        if (nTotalCheckpoints > 0 && totalVoteCount[nTotalCheckpoints - 1].fromBlock == blockNumber) {
            totalVoteCount[nTotalCheckpoints - 1].voteCount = newTotalVotes;
            totalVoteCount[nTotalCheckpoints - 1].delegatedVoteCount = newTotalDelegatedVotes;
            totalVoteCount[nTotalCheckpoints - 1].isDelegating = delegated;
        } else {
            totalVoteCount[nTotalCheckpoints] = Checkpoint(blockNumber, newTotalVotes, newTotalDelegatedVotes, delegated);
            totalVoteNumCheckpoints = nTotalCheckpoints + 1;
        }
    }

    /// @notice Iterate all the checkpoints to find the balance at the given block number.
    /// @param  blockNumber block number
    /// @param  _nCheckpoints number of checkpoints
    /// @param  _checkpoints all checkpoints
    /// @return uint256 balance at the given block
    function _iterateCheckpoints(uint blockNumber, uint _nCheckpoints, mapping(uint => Checkpoint) storage _checkpoints)
    internal view returns (uint256, uint256, bool) {

        if (_nCheckpoints == 0) {
            return (0, 0, false);
        }

        // First check most recent balance
        if (_checkpoints[_nCheckpoints - 1].fromBlock <= blockNumber) {
            return (_checkpoints[_nCheckpoints - 1].voteCount, _checkpoints[_nCheckpoints - 1].delegatedVoteCount,
                _checkpoints[_nCheckpoints - 1].isDelegating);
        }

        // Next check implicit zero balance
        if (_checkpoints[0].fromBlock > blockNumber) {
            return (0, 0, false);
        }

        uint lower = 0;
        uint upper = _nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2;
            // ceil, avoiding overflow
            Checkpoint memory cp = _checkpoints[center];
            if (cp.fromBlock == blockNumber) {
                return (cp.voteCount, cp.delegatedVoteCount, cp.isDelegating);
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return (_checkpoints[lower].voteCount, _checkpoints[lower].delegatedVoteCount, _checkpoints[lower].isDelegating);
    }

    /// @notice Calculates the user's multiplier based on its locking period.
    /// @param  period locking period, in weeks
    /// @return uint256 multiplier
    function calculateMultiplier(uint period) internal pure returns (uint256) {
        uint256 periodInWei = period.mul(10 ** uint256(18));
        uint256 weightInWei = uint256(1).add((uint256(2).mul(periodInWei.sqrt())).div(10));

        uint256 numerator = (weightInWei.sub(1)).mul(WEIGHT_MULTIPLIER);
        uint256 denominator = (10 ** uint256(18)).sqrt();
        return numerator.div(denominator).add(WEIGHT_MULTIPLIER);
    }

    /// @notice Removes index element from the given array.
    /// @param  index index to remove from the array
    /// @param  array the array itself
    function removeElementFromArray(uint256 index, uint256[] storage array) private {
        if (index == array.length - 1) {
            array.pop();
        } else {
            array[index] = array[array.length - 1];
            array.pop();
        }
    }

    /// @notice Checks if a governor has delegated to other governor
    /// @param  governor address to check
    /// @return bool true/false
    function checkDelegation(address governor) external view override returns (bool) {
        return hasDelegated[governor];
    }

    /// @notice Gets the delegated votes per user
    /// @param  delegator address to check
    /// @return uint256 delegated votes
    function delegatedVotesCount(address delegator) external view override returns (uint256) {
        return userDelegatedVotesCount[delegator];
    }

    /// @notice Gets the plenny locked by user
    /// @param  user address to check
    /// @return uint256 locked plenny
    function userPlennyLocked(address user) external view override returns (uint256) {
        return userValueLocked[user];
    }
}

