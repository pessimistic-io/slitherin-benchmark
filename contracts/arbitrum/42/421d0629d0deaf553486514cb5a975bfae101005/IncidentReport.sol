// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
  *******         **********     ***********     *****     ***********
  *      *        *              *                 *       *
  *        *      *              *                 *       *
  *         *     *              *                 *       *
  *         *     *              *                 *       *
  *         *     **********     *       *****     *       ***********
  *         *     *              *         *       *                 *
  *         *     *              *         *       *                 *
  *        *      *              *         *       *                 *
  *      *        *              *         *       *                 *
  *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import "./OwnableWithoutContextUpgradeable.sol";

import "./IncidentReportParameters.sol";
import "./IncidentReportDependencies.sol";
import "./IncidentReportEventError.sol";

import "./ExternalTokenDependencies.sol";

/**
 * @notice Incident Report Contract
 *
 *         New reports for project hacks are handled inside this contract
 *
 *         Timeline for a report is:
 *
 *         |-----------------------|----------------------|-------|-------|
 *               Pending Period         Voting Period       Extend Period
 *
 *         When a new report is proposed, it start with PENDING_STATUS.
 *         The person who start the report need to deposit REPORT_THRESHOLD DEG tokens.
 *         During PENDING_STATUS, users & security companies can look at the report event.
 *
 *         After PENDING_PERIOD, the voting can be started and status transfer to VOTING_STATUS.
 *         Users can vote for or against the report with veDeg tokens.
 *         VeDeg tokens used for voting will be tentatively locked until the voting is settled.
 *
 *         After VOTING_PERIOD, the voting can be settled and status transfer to SETTLED_STATUS.
 *         Depending on the votes of each side, the result can be PASSED, REJECTED or TIED.
 *         Different results for their veDeg tokens will be set depending on the result.
 *
 *         If the result has changes during the last 24 hours of voting, the voting will be extended.
 *         The time can only be extended twice.
 *
 *         For voters:
 *              PASSED: Who vote for will get all veDeg tokens from the opposite side
 *              REJECTED: Who vote against will get all veDeg tokens from the opposite side
 *              TIED: Users can unlock their veDeg tokens
 *         For reporter:
 *              PASSED: Get back REPORT_THRESHOLD and get extra REPORT_REWARD & 10% of total treasury income
 *              REJECTED: Lose REPORT_THRESHOLD to whom vote against
 *              TIED: Lose REPORT_THRESHOLD
 *
 *         When an incident report has passed and been executed
 *         The corresponding priority pool will be liquidated which means:
 *             - Move out some assets for users to claim
 *             - Deploy new generation of crTokens and PRI-LP tokens
 *             - Update the farming weights for the priority farming pool
 *
 */
contract IncidentReport is
    IncidentReportParameters,
    IncidentReportEventError,
    OwnableWithoutContextUpgradeable,
    ExternalTokenDependencies,
    IncidentReportDependencies
{
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Total number of reports
    uint256 public reportCounter;

    // Report quorum ratio
    uint256 public quorumRatio;

    struct Report {
        uint256 poolId; // Project pool id
        uint256 reportTimestamp; // Time of starting report
        address reporter; // Reporter address
        uint256 voteTimestamp; // Voting start timestamp
        uint256 numFor; // Votes voting for
        uint256 numAgainst; // Votes voting against
        uint256 round; // 0: Initial round 3 days, 1: Extended round 1 day, 2: Double extended 1 day
        uint256 status; // 0: INIT, 1: PENDING, 2: VOTING, 3: SETTLED, 404: CLOSED
        uint256 result; // 1: Pass, 2: Reject, 3: Tied
        uint256 votingReward; // Voting reward per veDEG
        uint256 payout; // Payout amount of this report (partial payout)
    }
    // Report id => Report
    mapping(uint256 => Report) public reports;

    // Pool id => All related reports
    mapping(uint256 => uint256[]) public poolReports;

    struct TempResult {
        uint256 result;
        uint256 sampleTimestamp;
        bool hasChanged;
    }
    mapping(uint256 => TempResult) public tempResults;

    struct UserVote {
        uint256 choice; // 1: vote for, 2: vote against
        uint256 amount; // total veDEG amount for voting
        bool claimed; // whether has claimed the reward
        bool paid; // whether has paid the debt   // @audit Add paid status
    }
    // User address => report id => user's voting info
    mapping(address => mapping(uint256 => UserVote)) public votes;

    // Pool id => whether the pool is being reported
    mapping(uint256 => bool) public reported;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(
        address _deg,
        address _veDeg
    ) public initializer {
        __Ownable_init();
        __ExternalToken__Init(_deg, _veDeg);

        // Initial quorum 50%
        quorumRatio = 50;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    function getUserVote(address _user, uint256 _poolId)
        external
        view
        returns (UserVote memory)
    {
        return votes[_user][_poolId];
    }

    function getTempResult(uint256 _poolId)
        external
        view
        returns (TempResult memory)
    {
        return tempResults[_poolId];
    }

    function getReport(uint256 _id) public view returns (Report memory) {
        return reports[_id];
    }

    function getPoolReports(uint256 _poolId)
        external
        view
        returns (uint256[] memory)
    {
        return poolReports[_poolId];
    }

    function getPoolReportsAmount(uint256 _poolId)
        external
        view
        returns (uint256)
    {
        return poolReports[_poolId].length;
    }


    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    function setPriorityPoolFactory(address _priorityPoolFactory)
        external
        onlyOwner
    {
        priorityPoolFactory = IPriorityPoolFactory(_priorityPoolFactory);
    }

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
    }

    function setQuorumRatio(uint256 _ratio) external onlyOwner {
        if (_ratio >= 100) revert IncidentReport__QuorumRatioTooBig();
        quorumRatio = _ratio;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Start a new incident report
     *
     *         1000 DEG tokens are staked to start a report
     *         If the report is correct, reporter gets back 1000DEG + 10% usdc income + extra 1000DEG
     *         If the report is wrong, reporter loses 1000DEG to those who vote against
     *         Only callable through proposal center
     *
     * @param _poolId Pool id to report incident
     * @param _payout Payout amount of this report
     */
    function report(uint256 _poolId, uint256 _payout) external onlyOwner {
        _report(_poolId, _payout, msg.sender);
    }

    /**
     * @notice Start the voting process
     *
     *         Can only be started after the pending period
     *         Will change the status from PENDING to VOTING
     *
     * @param _id Report id
     */
    function startVoting(uint256 _id) external {
        Report storage currentReport = reports[_id];
        if (currentReport.status != PENDING_STATUS)
            revert IncidentReport__WrongStatus();

        // Can only start the voting after pending period
        if (!_passedPendingPeriod(currentReport.reportTimestamp))
            revert IncidentReport__WrongPeriod();

        currentReport.status = VOTING_STATUS;
        currentReport.voteTimestamp = block.timestamp;

        emit ReportVotingStart(_id, block.timestamp);
    }

    /**
     * @notice Close a pending report
     *
     *         Only owner can close a pending report
     *         Can only be closed before the pending period ends
     *         Will change the status from PENDING to CLOSED
     *
     * @param _id Report id
     */
    function closeReport(uint256 _id) external onlyOwner {
        Report storage currentReport = reports[_id];
        if (currentReport.status != PENDING_STATUS)
            revert IncidentReport__WrongStatus();

        // Must close the report before pending period ends
        if (_passedPendingPeriod(currentReport.reportTimestamp))
            revert IncidentReport__WrongPeriod();

        currentReport.status = CLOSE_STATUS;

        _setReportedStatus(_id, false);

        poolReports[currentReport.poolId].pop();

        _unpausePools(currentReport.poolId);

        emit ReportClosed(_id, block.timestamp);
    }

    /**
     * @notice Vote on current reports
     *
     *         Voting power is decided by the (unlocked) balance of veDEG
     *         Once voted, those veDEG will be locked
     *         Rewarded if votes with majority
     *         Punished if votes against majority
     *
     * @param _id     Id of the report to be voted on
     * @param _isFor  The user's choice (1: vote for, 2: vote against)
     * @param _amount Amount of veDEG used for this vote
     */
    function vote(
        uint256 _id,
        uint256 _isFor,
        uint256 _amount
    ) external {
        _vote(_id, _isFor, _amount, msg.sender);
    }

    /**
     * @notice Settle the final result for a report
     *
     * @param _id Report id
     */
    function settle(uint256 _id) external {
        Report storage currentReport = reports[_id];

        if (currentReport.status != VOTING_STATUS)
            revert IncidentReport__WrongStatus();

        // Check has passed the voting period
        if (
            !_passedVotingPeriod(
                currentReport.round,
                currentReport.voteTimestamp
            )
        ) revert IncidentReport__WrongPeriod();

        if (currentReport.result > 0) revert IncidentReport__AlreadySettled();

        uint256 res = _checkRoundExtended(_id, currentReport.round);

        if (res > 0) {
            currentReport.status = SETTLED_STATUS;
            if (_checkQuorum(currentReport.numFor + currentReport.numAgainst)) {
                // REJECT or TIED: unlock the priority pool & protection pool immediately
                //                 mark the report as not reported
                if (res != PASS_RESULT) {
                    uint256 poolId = currentReport.poolId;
                    _unpausePools(poolId);
                    _setReportedStatus(poolId, false);

                    poolReports[poolId].pop();
                }

                currentReport.result = res;

                _settleVotingReward(_id, res);
                emit ReportSettled(_id, res);
            } else {
                currentReport.result = FAILED_RESULT;
                uint256 poolId = currentReport.poolId;

                // FAILED: unlock the priority pool & protection pool immediately
                _unpausePools(poolId);
                _setReportedStatus(poolId, false);

                emit ReportFailed(_id);
            }
        } else {
            tempResults[_id].hasChanged = false;

            emit ReportExtended(_id, currentReport.round);
        }
    }

    /**
     * @notice Claim the voting reward
     *         Only callable through proposal center
     *
     * @param _id Report id
     */
    function claimReward(uint256 _id) external {
        _claimReward(_id, msg.sender);
    }

    /**
     * @notice Pay debt to get back veDEG
     *
     *         For those who made a wrong voting choice
     *         The paid DEG will be burned and the veDEG will be unlocked
     *
     *         Can not call this function when result is TIED or choose the correct side
     *
     * @param _id   Report id
     * @param _user User address (can pay debt for another user)
     */
    function payDebt(uint256 _id, address _user) external {
        UserVote memory userVote = votes[_user][_id];
        uint256 finalResult = reports[_id].result;

        if (finalResult == 0) revert IncidentReport__NotSettled();
        if (
            userVote.choice == finalResult ||
            finalResult == TIED_RESULT ||
            finalResult == FAILED_RESULT
        ) revert IncidentReport__NotWrongChoice();
        // @audit Add paid status
        if (userVote.paid) revert IncidentReport__AlreadyPaid();

        uint256 debt = (userVote.amount * DEBT_RATIO) / 10000;

        // Pay the debt in DEG
        deg.burnDegis(msg.sender, debt);

        // Unlock the user's veDEG
        veDeg.unlockVeDEG(_user, userVote.amount);

        // @audit Add paid status
        votes[_user][_id].paid = true;

        emit DebtPaid(msg.sender, _user, debt, userVote.amount);
    }

    function unpausePools(uint256 _poolId) external onlyOwner {
        _unpausePools(_poolId);
    }

    /**
     * @notice Update status after execution
     *         Only callable by executor
     *
     * @param _reportId Report id
     */
    function executed(uint256 _reportId) external {
        if (msg.sender != executor) revert IncidentReport__OnlyExecutor();

        uint256 poolId = reports[_reportId].poolId;
        _setReportedStatus(poolId, false);
        _unpausePools(poolId);
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Internal Functions ********************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Start a new incident report
     *
     *         1000 DEG tokens are staked to start a report
     *         If the report is correct, reporter gets back 1000DEG + 10% usdc income + extra 1000DEG
     *         If the report is wrong, reporter loses 1000DEG to those who vote against
     *
     * @param _poolId Pool id to report incident
     * @param _payout Payout amount of this report
     * @param _user   Reporter
     */
    function _report(
        uint256 _poolId,
        uint256 _payout,
        address _user
    ) internal {
        // Check whether the pool can be reported
        _checkPoolStatus(_poolId, _payout);

        // Mark as already reported
        _setReportedStatus(_poolId, true);

        uint256 currentId = ++reportCounter;
        // Record the new report
        Report storage newReport = reports[currentId];
        newReport.poolId = _poolId;
        newReport.reportTimestamp = block.timestamp;
        newReport.reporter = _user;
        newReport.status = PENDING_STATUS;
        newReport.payout = _payout;

        // Burn degis tokens to start a report
        // Need to add this smart contract to burner list
        // deg.burnDegis(_user, REPORT_THRESHOLD);

        // Record this report id to this pool's all reports list
        poolReports[_poolId].push(currentId);

        // Pause pools immediately when report
        _pausePools(_poolId);

        emit ReportCreated(currentId, _poolId, block.timestamp, _user, _payout);
    }

    /**
     * @notice Vote on current reports
     *
     *         Voting power is decided by the (unlocked) balance of veDEG
     *         Once voted, those veDEG will be locked
     *         Rewarded if votes with majority
     *         Punished if votes against majority
     *
     * @param _id       Id of the report to be voted on
     * @param _isFor    The user's choice (1: vote for, 2: vote against)
     * @param _amount   Amount of veDEG used for this vote
     * @param _user     The user who votes on the incidnet
     */
    function _vote(
        uint256 _id,
        uint256 _isFor,
        uint256 _amount,
        address _user
    ) internal {
        // Should be manually switched on the voting process
        if (reports[_id].status != VOTING_STATUS)
            revert IncidentReport__WrongStatus();
        if (_amount == 0) revert IncidentReport__ZeroAmount();
        if (_isFor != VOTE_FOR && _isFor != VOTE_AGAINST)
            revert IncidentReport__WrongChoice();

        _enoughVeDEG(_user, _amount);

        // Lock vedeg until this report is settled
        _lockVeDEG(_user, _amount);

        // Record the user's choice
        UserVote storage userVote = votes[_user][_id];
        if (userVote.amount > 0) {
            if (userVote.choice != _isFor)
                revert IncidentReport__ChooseBothSides();
        } else {
            userVote.choice = _isFor;
        }
        userVote.amount += _amount;

        Report storage currentReport = reports[_id];
        // Record the vote for this report
        if (_isFor == VOTE_FOR) {
            currentReport.numFor += _amount;
        } else {
            currentReport.numAgainst += _amount;
        }

        // Record a temporary result
        // If the hasChanged already been true, no need for further update
        // If not reached the last day, no need for update
        if (
            !tempResults[_id].hasChanged &&
            _withinSamplePeriod(
                currentReport.voteTimestamp,
                currentReport.round
            )
        ) {
            _recordTempResult(
                _id,
                currentReport.numFor,
                currentReport.numAgainst
            );
        }

        emit ReportVoted(_id, _user, _isFor, _amount);
    }

    /**
     * @notice Claim the voting reward
     *
     *         Only called when:
     *         - Result is TIED or FAILED
     *         - Result is PASS or REJECT and you have the correct choice
     *
     *         If the result is TIED or FAILED, only unlock veDEG
     *         If the result is the same as your choice, get the reward
     *
     * @param _id   Report id
     * @param _user User address
     */
    function _claimReward(uint256 _id, address _user) internal {
        UserVote memory userVote = votes[_user][_id];
        uint256 finalResult = reports[_id].result;

        if (finalResult == INIT_RESULT) revert IncidentReport__NotSettled();
        if (userVote.claimed) revert IncidentReport__AlreadyClaimed();

        // Correct choice
        if (userVote.choice == finalResult) {
            uint256 reward = reports[_id].votingReward * userVote.amount;
            deg.mintDegis(_user, reward / SCALE);

            _unlockVeDEG(_user, userVote.amount);
        }
        // Tied result, give back user's veDEG
        else if (finalResult == TIED_RESULT || finalResult == FAILED_RESULT) {
            _unlockVeDEG(_user, userVote.amount);
        }
        // Wrong choice, no reward
        else revert IncidentReport__NoReward();

        votes[_user][_id].claimed = true;
    }

    /**
     * @notice Settle voting reward depending on the result
     *
     * @param _id     Report id
     * @param _result Settle result
     */
    function _settleVotingReward(uint256 _id, uint256 _result) internal {
        Report storage currentReport = reports[_id];

        uint256 numFor = currentReport.numFor;
        uint256 numAgainst = currentReport.numAgainst;

        uint256 totalRewardToVoters;

        if (_result == PASS_RESULT) {
            // Get back REPORT_THRESHOLD and get extra REPORTER_REWARD deg tokens
            deg.mintDegis(
                currentReport.reporter,
                REPORTER_REWARD + REPORT_THRESHOLD
            );

            // 40% of total deg reward to the opposite (deg amount)
            // REWARD_RATIO is 100 max
            // veDEG => DEG also divided by 100
            totalRewardToVoters = (numAgainst * REWARD_RATIO) / 10000;

            // Update deg reward for those who vote for
            currentReport.votingReward = (totalRewardToVoters * SCALE) / numFor;
        } else if (_result == REJECT_RESULT) {
            // Total deg reward = reporter's DEG + those who vote for
            totalRewardToVoters =
                REPORT_THRESHOLD +
                (numFor * REWARD_RATIO) /
                10000;

            // Update deg reward for those who vote against
            currentReport.votingReward =
                (totalRewardToVoters * SCALE) /
                numAgainst;
        }

        emit VotingRewardSettled(_id, totalRewardToVoters);
    }

    /**
     * @notice Check quorum requirement
     *         30% of totalSupply is the minimum requirement for participation
     *
     * @param _totalVotes Total vote numbers
     */
    function _checkQuorum(uint256 _totalVotes) internal view returns (bool) {
        return
            _totalVotes >=
            (SimpleIERC20(veDeg).totalSupply() * quorumRatio) / 100;
    }

    /**
     * @notice Check veDEG to be enough
     *
     * @param _user   User address
     * @param _amount Amount to fulfill
     */
    function _enoughVeDEG(address _user, uint256 _amount) internal view {
        uint256 unlockedBalance = veDeg.balanceOf(_user) - veDeg.locked(_user);
        if (unlockedBalance < _amount) revert IncidentReport__NotEnoughVeDEG();
    }

    /**
     * @notice Check whether has passed the pending time period
     *
     * @param _reportTimestamp Start timestamp of the report
     *
     * @return hasPassed True for passing
     */
    function _passedPendingPeriod(uint256 _reportTimestamp)
        internal
        view
        returns (bool)
    {
        return block.timestamp >= _reportTimestamp + PENDING_PERIOD;
    }

    /**
     * @notice Check whether has passed the voting time period
     *
     * @param _round         Current round
     * @param _voteTimestamp Start timestamp of the report voting
     *
     * @return hasPassed True for passing
     */
    function _passedVotingPeriod(uint256 _round, uint256 _voteTimestamp)
        internal
        view
        returns (bool)
    {
        uint256 endTime = _voteTimestamp +
            INCIDENT_VOTING_PERIOD +
            _round *
            EXTEND_PERIOD;
        return block.timestamp >= endTime;
    }

    /**
     * @notice Check whether this round need extend
     *
     * @param _id    Report id
     * @param _round Current round
     *
     * @return result 0 for extending, 1/2/3 for final result
     */
    function _checkRoundExtended(uint256 _id, uint256 _round)
        internal
        returns (uint256 result)
    {
        bool hasChanged = tempResults[_id].hasChanged;

        if (hasChanged && _round < MAX_EXTEND_ROUND) {
            _extendRound(_id);
        } else {
            result = _getVotingResult(
                reports[_id].numFor,
                reports[_id].numAgainst
            );
        }
    }

    /**
     * @notice Extend the current round
     *
     * @param _id Report id
     */
    function _extendRound(uint256 _id) internal {
        unchecked {
            ++reports[_id].round;
        }
    }

    /**
     * @notice Record a temporary result when goes in the sampling period
     *
     *         Temporary result use 1 for "pass" and 2 for "reject"
     *
     * @param _id         Report id
     * @param _numFor     Vote numbers for
     * @param _numAgainst Vote numbers against
     */
    function _recordTempResult(
        uint256 _id,
        uint256 _numFor,
        uint256 _numAgainst
    ) internal {
        TempResult storage temp = tempResults[_id];

        uint256 currentResult = _getVotingResult(_numFor, _numAgainst);

        // If this is the first time for sampling, not record hasChange state
        if (temp.result > 0) {
            temp.hasChanged = currentResult != temp.result;
        }

        // Store the current result and sample time
        temp.result = currentResult;
        temp.sampleTimestamp = block.timestamp;
    }

    /**
     * @notice Check time is within sample period
     *
     * @param _voteTimestamp Vote start timestamp
     * @param _round         Current round
     */
    function _withinSamplePeriod(uint256 _voteTimestamp, uint256 _round)
        internal
        view
        returns (bool)
    {
        uint256 endTime = _voteTimestamp +
            INCIDENT_VOTING_PERIOD +
            _extendTime(_round);

        uint256 lastDayStart = _voteTimestamp +
            INCIDENT_VOTING_PERIOD +
            _extendTime(_round) -
            SAMPLE_PERIOD;

        return block.timestamp > lastDayStart && block.timestamp < endTime;
    }

    /**
     * @notice Get the final voting result
     *
     * @param _numFor     Votes for
     * @param _numAgainst Votes against
     *
     * @return result PASS(1), REJECT(2) or TIED(3)reported
     */
    function _getVotingResult(uint256 _numFor, uint256 _numAgainst)
        internal
        pure
        returns (uint256 result)
    {
        if (_numFor > _numAgainst) result = PASS_RESULT;
        else if (_numFor < _numAgainst) result = REJECT_RESULT;
        else result = TIED_RESULT;
    }

    /**
     * @notice Check pool status and return address
     *         Ensure the pool:
     *             1) Exists
     *             2) Has not been reported'
     *             3) The payout is less than the active covered amount
     *
     * @param _poolId Pool id
     * @param _payout Payout amount
     *
     */
    function _checkPoolStatus(uint256 _poolId, uint256 _payout) internal view {
        (, address pool, , , ) = priorityPoolFactory.pools(_poolId);

        if (pool == address(0)) revert IncidentReport__PoolNotExist();
        if (reported[_poolId]) revert IncidentReport__AlreadyReported();

        if (_payout > ISimplePriorityPool(pool).activeCovered())
            revert IncidentReport__PayoutExceedCovered();
    }

    /**
     * @notice Pause the related priority pool and protection pool
     *         Once there is an incident reported and voting start
     *
     * @param _poolId Priority pool id
     */
    function _pausePools(uint256 _poolId) internal {
        IPriorityPoolFactory(priorityPoolFactory).pausePriorityPool(
            _poolId,
            true
        );
    }

    /**
     * @notice Unpause the related project pool and the re-insurance pool
     *         When the report was REJECTED / TIED / FAILED, unlock immediately
     *         When the report was PASSED, unlock when executor execute it
     *
     * @param _poolId Priority pool id
     */
    function _unpausePools(uint256 _poolId) internal {
        IPriorityPoolFactory(priorityPoolFactory).pausePriorityPool(
            _poolId,
            false
        );
    }

    /**
     * @notice Calculate the extend time
     *
     * @param _round Rounds to extend
     *
     * @return extendTime Extend time length
     */
    function _extendTime(uint256 _round) internal pure returns (uint256) {
        return _round * EXTEND_PERIOD;
    }

    /**
     * @notice Unlock veDEG
     *
     * @param _user   User address
     * @param _amount Amount to unlock
     */
    function _unlockVeDEG(address _user, uint256 _amount) internal {
        veDeg.unlockVeDEG(_user, _amount);
    }

    /**
     * @notice Lock veDEG
     *
     * @param _user   User address
     * @param _amount Amount to lock
     */
    function _lockVeDEG(address _user, uint256 _amount) internal {
        veDeg.lockVeDEG(_user, _amount);
    }

    /**
     * @notice Set reported status for a pool
     *
     * @param _poolId   Pool id
     * @param _reported Whether already reported
     */
    function _setReportedStatus(uint256 _poolId, bool _reported) internal {
        reported[_poolId] = _reported;
    }
}

