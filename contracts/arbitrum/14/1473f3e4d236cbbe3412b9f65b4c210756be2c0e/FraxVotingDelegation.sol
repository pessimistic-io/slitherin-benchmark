// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== FraxVotingDelegation ===================
// ====================================================================
// # FraxVotingDelegation

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch
// Jamie Turley: https://github.com/jyturley

import {SafeCast} from "./SafeCast.sol";
import "./Math.sol";
import "./IVeFxs.sol";

abstract contract FraxVotingDelegation {
    using SafeCast for uint256;

    uint256 public constant WEEK = 7 days;
    uint256 public constant VOTE_WEIGHT_MULTIPLIER = 3;

    uint256 public minimumVeFxsForGovernance;

    IVeFxs public immutable _VE_FXS;

    //mapping(address delgator => Delegation delegate) private _delegates;
    mapping(address => Delegation) public delegates;
    //mapping(address delegate => DelegateCheckpoint[]) private _checkpoints;
    mapping(address => DelegateCheckpoint[]) public checkpoints;
    //mapping(address delegate => mapping(uint256 week => Expiration)) expirations;
    mapping(address => mapping(uint256 => Expiration)) public expirations;

    //    mapping(address delegate => uint256 lastExpiration) private _expirationTimestamps;
    mapping(address => uint256) public lastExpirations;

    error OnlyVeFxs();
    error CantDelegateToSelf();
    error CantDelegateLockExpired();
    error TimestampInFuture();

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// A representation of a delegate and all its delegators at a particular timestamp
    struct DelegateCheckpoint {
        uint128 normalizedBias;
        uint128 totalFxs;
        // _________
        uint128 normalizedSlope;
        uint128 timestamp; // Rounded up to the nearest day
    }

    /// Represents the total bias, slope, and FXS amount of all accounts that expire in a particular week
    struct Expiration {
        uint256 bias;
        // _________
        uint128 fxs;
        uint128 slope;
    }

    /// Represents the values of a single delegation at the time `delegate()` is called,
    /// to be subtracted when removing delegation
    struct Delegation {
        uint256 bias;
        // _________
        uint128 fxs;
        uint128 slope;
        // _________
        address delegate;
        uint48 timestamp;
        uint48 expiry;
    }

    /**
     * @notice Ensure functions can only be called by veFXS holders
     */
    function _requireVeFxsHolder(address account) internal view {
        if (_VE_FXS.balanceOf(account) < minimumVeFxsForGovernance) revert OnlyVeFxs();
    }

    constructor(address veFxs) {
        _VE_FXS = IVeFxs(veFxs);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function getCheckpoint(address account, uint32 pos) external view returns (DelegateCheckpoint memory) {
        return checkpoints[account][pos];
    }

    /**
     * @dev Get the address `account` is currently delegating to.
     */
    function delegatedTo(address account) external view returns (address) {
        return delegates[account].delegate;
    }

    function _calculateDelegatedWeight(address account, uint256 timestamp) internal view returns (uint256) {
        // Check if account has any delegations
        DelegateCheckpoint memory checkpoint =
            _checkpointLookup({_checkpoints: checkpoints[account], timestamp: timestamp});
        if (checkpoint.timestamp == 0) {
            return 0;
        }

        // It's possible that some delegated veFXS has expired.
        // Add up all expirations during this time period, week by week.
        (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredFxs) =
            _calculateExpiration({account: account, start: checkpoint.timestamp, end: timestamp});

        uint256 expirationAdjustedBias = checkpoint.normalizedBias - totalExpiredBias;
        uint256 expirationAdjustedSlope = checkpoint.normalizedSlope - totalExpiredSlope;
        uint256 expirationAdjustedFxs = checkpoint.totalFxs - totalExpiredFxs;

        uint256 voteDecay = expirationAdjustedSlope * timestamp;
        uint256 biasAtTimestamp = (expirationAdjustedBias > voteDecay) ? expirationAdjustedBias - voteDecay : 0;

        // expirationAdjustedFxs + ...
        return expirationAdjustedFxs + (VOTE_WEIGHT_MULTIPLIER * biasAtTimestamp);
    }

    function _calculateWeight(address account, uint256 timestamp) internal view returns (uint256) {
        if (_VE_FXS.locked(account).end <= timestamp) return 0;

        Delegation memory delegation = delegates[account];

        if (
            delegation.delegate == address(0) && timestamp >= delegation.timestamp // undelegated but old delegation still in effect until next epoch
                || delegation.delegate != address(0) && timestamp < delegation.timestamp // delegated but delegation not in effect until next epoch
        ) {
            return _VE_FXS.balanceOf({addr: account, _t: timestamp});
        }

        return 0;
    }

    /**
     * @notice Ask veFXS for a given user's voting power at a certain timestamp
     * @param account Voter address
     * @param timestamp To ensure voter has sufficient power at the time of proposal
     */
    function _getVoteWeight(address account, uint256 timestamp) internal view returns (uint256) {
        if (timestamp > block.timestamp) revert TimestampInFuture();

        return _calculateWeight({account: account, timestamp: timestamp})
            + _calculateDelegatedWeight({account: account, timestamp: timestamp});
    }

    /**
     * @dev Delegate votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) external {
        _delegate({delegator: msg.sender, delegatee: delegatee});
    }

    /**
     * @param delegator Account whos votes will transferred from.
     * @param delegatee New account delegator will delegate to.
     * @dev An account can only delegate to one account at a time. The previous delegation will be overwritten.
     * @dev To undelegate, `delegatee` should be 0x0...0
     */
    function _delegate(address delegator, address delegatee) internal {
        if (delegator == delegatee) revert CantDelegateToSelf();
        _requireVeFxsHolder(delegator);

        Delegation memory previousDelegation = delegates[delegator];
        (uint256 delegatorBias, uint256 delegatorSlope, uint256 delegatorFxs, uint256 delegatorExpiry) =
            _getCorrectedInfo(delegator);
        uint256 checkpointTimestamp = ((block.timestamp / 1 days) * 1 days) + 1 days;

        _moveVotingPower({
            previousDelegation: previousDelegation,
            newDelegate: delegatee,
            currentBias: delegatorBias,
            currentSlope: delegatorSlope,
            currentFxs: delegatorFxs,
            currentExpiry: delegatorExpiry,
            checkpointTimestamp: checkpointTimestamp
        });

        delegates[delegator] = Delegation({
            delegate: delegatee,
            timestamp: uint48(checkpointTimestamp),
            bias: delegatorBias,
            slope: uint128(delegatorSlope),
            expiry: uint48(delegatorExpiry),
            fxs: uint128(delegatorFxs)
        });

        emit DelegateChanged({delegator: delegator, fromDelegate: previousDelegation.delegate, toDelegate: delegatee});
    }

    /**
     * @notice Get the most recently recorded rate of voting power decrease for `account`
     * @param account Address of the user wallet
     */
    function _getCorrectedInfo(address account)
        private
        view
        returns (uint256 bias, uint256 slope, uint256 fxs, uint256 expiry)
    {
        // most recent epoch
        uint256 epoch = _VE_FXS.user_point_epoch(account);
        // values for account at the most recent epoch
        (int128 uBias, int128 uSlope,,, uint256 uFxs) = _VE_FXS.user_point_history({_addr: account, _idx: epoch});
        slope = SafeCast.toUint256(uSlope);
        fxs = uFxs;
        expiry = _VE_FXS.locked(account).end;

        if (expiry <= block.timestamp) revert CantDelegateLockExpired();

        uint256 lastUpdate = _VE_FXS.user_point_history__ts({_addr: account, _idx: epoch});
        // normalize bias to unix epoch, so all biases can be added and subtracted directly
        bias = SafeCast.toUint256(uBias) + slope * lastUpdate;
        return (bias, slope, fxs, expiry);
    }

    /**
     * @dev Lookup a value in a list of (sorted) checkpoints.
     */
    function _checkpointLookup(DelegateCheckpoint[] storage _checkpoints, uint256 timestamp)
        private
        view
        returns (DelegateCheckpoint memory)
    {
        uint256 high = _checkpoints.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_checkpoints[mid].timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        DelegateCheckpoint memory empty;
        return high == 0 ? empty : _checkpoints[high - 1];
    }

    /**
     * @dev Used in _delegate() when an account changes delegation
     */
    function _moveVotingPower(
        Delegation memory previousDelegation,
        address newDelegate,
        uint256 currentBias,
        uint256 currentSlope,
        uint256 currentFxs,
        uint256 currentExpiry,
        uint256 checkpointTimestamp
    ) private {
        // Remove voting power from previous delegate, if they exist
        if (previousDelegation.delegate != address(0)) {
            _writeCheckpoint({
                account: previousDelegation.delegate,
                op: _subtract,
                deltaBias: previousDelegation.bias,
                deltaSlope: previousDelegation.slope,
                deltaFxs: previousDelegation.fxs,
                checkpointTimestamp: checkpointTimestamp
            });
            _writeExpiration({
                account: previousDelegation.delegate,
                op: _subtract,
                bias: previousDelegation.bias,
                slope: previousDelegation.slope,
                expiry: previousDelegation.expiry,
                fxs: previousDelegation.fxs
            });
        }

        // Add voting power to new delegate
        if (newDelegate != address(0)) {
            _writeCheckpoint({
                account: newDelegate,
                op: _add,
                deltaBias: currentBias,
                deltaSlope: currentSlope,
                deltaFxs: currentFxs,
                checkpointTimestamp: checkpointTimestamp
            });
            _writeExpiration({
                account: newDelegate,
                op: _add,
                bias: currentBias,
                slope: currentSlope,
                expiry: currentExpiry,
                fxs: currentFxs
            });
        }
    }

    /**
     * @notice Write to storage the bias and slopes of a given account.
     * @dev This is either a subtraction or addition based on if an account is
     * adding or undoing a delegation.
     */
    function _writeExpiration(
        address account,
        function(uint256, uint256) view returns (uint256) op,
        uint256 bias,
        uint256 slope,
        uint256 expiry,
        uint256 fxs
    ) private {
        Expiration storage expiration = expirations[account][expiry];
        expiration.bias = op(expiration.bias, bias);
        expiration.slope = uint128(op(uint256(expiration.slope), slope));
        expiration.fxs = uint128(op(uint256(expiration.fxs), fxs));
        if (expiration.fxs > 0 && lastExpirations[account] < expiry) {
            lastExpirations[account] = expiry;
        }
    }

    /**
     * @notice Write to storage a new checkpoint for a delegate account
     * @dev New checkpoints are based on the most recent checkpoint, and can be additive
     * or subtractive depending on if an account is adding or undoing a delegation.
     */
    function _writeCheckpoint(
        address account,
        function(uint256, uint256) view returns (uint256) op,
        uint256 deltaBias,
        uint256 deltaSlope,
        uint256 deltaFxs,
        uint256 checkpointTimestamp
    ) private returns (uint256 newBias, uint256 newSlope, uint256 newFxs) {
        DelegateCheckpoint[] storage _checkpoints = checkpoints[account];
        uint256 position = _checkpoints.length;
        //            DelegateCheckpoint memory previousCheckpoint =
        //              position == 0 ? DelegateCheckpoint(0, 0, 0, 0) : _unsafeAccess(_checkpoints, position - 1);

        unchecked {
            DelegateCheckpoint memory previousCheckpoint =
                position == 0 ? DelegateCheckpoint(0, 0, 0, 0) : _checkpoints[position - 1];

            newBias = op(previousCheckpoint.normalizedBias, deltaBias);
            newSlope = op(previousCheckpoint.normalizedSlope, deltaSlope);
            newFxs = op(previousCheckpoint.totalFxs, deltaFxs);

            // Update the existing checkpoint.
            if (position > 0 && previousCheckpoint.timestamp == checkpointTimestamp) {
                //                _unsafeAccess(_checkpoints, position - 1).normalizedBias = newBias;
                //                _unsafeAccess(_checkpoints, position - 1).normalizedSlope = newSlope;
                //                _unsafeAccess(_checkpoints, position - 1).totalFxs = newFxs;
                _checkpoints[position - 1].normalizedBias = uint128(newBias);
                _checkpoints[position - 1].normalizedSlope = uint128(newSlope);
                _checkpoints[position - 1].totalFxs = uint128(newFxs);
                // Make a new checkpoint
            } else {
                {
                    // adjust for expirations
                    (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredFxs) =
                        _calculateExpiration(account, previousCheckpoint.timestamp, checkpointTimestamp);
                    newBias -= totalExpiredBias;
                    newSlope -= totalExpiredSlope;
                    newFxs -= totalExpiredFxs;
                }
                _checkpoints.push(
                    DelegateCheckpoint({
                        timestamp: uint128(checkpointTimestamp),
                        normalizedBias: uint128(newBias),
                        normalizedSlope: uint128(newSlope),
                        totalFxs: uint128(newFxs)
                    })
                );
            }
        }
    }

    /**
     * @notice Generate a summation of bias and slopes for all accounts whose decay expires
     * during a specified time window
     * @param account Delegate account to generate expiration bias and slopes for
     * @param start Timestamp to start the summations from
     * @param end Timestamp to end to summations
     */
    function _calculateExpiration(address account, uint256 start, uint256 end)
        private
        view
        returns (uint256 totalBias, uint256 totalSlope, uint256 expiredFxs)
    {
        // Total values will always be less than or equal to a checkpoint's values
        unchecked {
            uint256 currentWeek = WEEK + (start / WEEK) * WEEK;
            end = end < lastExpirations[account] ? end : lastExpirations[account];
            mapping(uint256 => Expiration) storage delegateExpirations = expirations[account];
            while (!(currentWeek > end)) {
                // currentWeek <= end
                Expiration memory expiration = delegateExpirations[currentWeek];
                totalBias += expiration.bias;
                totalSlope += expiration.slope;
                expiredFxs += expiration.fxs;
                currentWeek += WEEK;
            }
        }
    }

    /**
     * @dev Simple addition, used in _moveVotingPower()
     */
    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a + b;
        }
    }

    /**
     * @dev Simple subtraction, used in _moveVotingPower()
     */
    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a - b;
        }
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    //    TODO: busted when using with the same previous and new delegate, look at later to gas optimize
    //    function _unsafeAccess(DelegateCheckpoint[] storage _checkpoints, uint256 position)
    //        private
    //        pure
    //        returns (DelegateCheckpoint storage result)
    //    {
    //        assembly {
    //            mstore(0, _checkpoints.slot)
    //            result.slot := add(keccak256(0, 0x20), position)
    //        }
    //    }
}

