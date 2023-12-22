// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Math} from "./Math.sol";
import {SafeCast} from "./SafeCast.sol";
import {ECDSA} from "./ECDSA.sol";

import {ITokenVotes} from "./ITokenVotes.sol";

/// @notice Timestamp implementation of token based voting power and delegation.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/TokenVotes.sol)
abstract contract TokenVotes is ITokenVotes {
    mapping(address => address) private _delegates;
    mapping(address => Checkpoint[]) private _checkpoints;
    Checkpoint[] private _totalSupplyCheckpoints;

    /**
     * @dev Expose block chain ID for signatures
     */
    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    /**
     * @dev Get the address `account` is currently delegating to.
     */
    function delegates(address account) public view virtual override returns (address) {
        return _delegates[account];
    }

    /**
     * @dev Gets the current votes balance for `account`
     */
    function getVotes(address account) public view virtual override returns (uint256) {
        uint256 pos = _checkpoints[account].length;
        return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
    }

    /**
     * @dev Retrieve the number of votes for `account` after a `timestamp`.
     *
     * Requirements:
     *
     * - `timestamp` must be in the past
     */
    function getPastVotes(address account, uint256 timestamp) public view virtual override returns (uint256) {
        // if (timestamp >= block.timestamp) revert TokenVotes__TimeNotPast();
        return _checkpointsLookup(_checkpoints[account], timestamp);
    }

    /**
     * @dev Retrieve the `totalSupply` after a `timestamp`. Note, this value is the sum of all balances.
     * It is NOT the sum of all the delegated votes!
     *
     * Requirements:
     *
     * - `timestamp` must be in the past
     */
    function getPastTotalSupply(uint256 timestamp) public view virtual override returns (uint256) {
        // if (timestamp >= block.timestamp) revert TokenVotes__TimeNotPast();
        return _checkpointsLookup(_totalSupplyCheckpoints, timestamp);
    }

    /**
     * @dev Lookup a value in a list of (sorted) checkpoints.
     */
    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 timestamp) private view returns (uint256) {
        // We run a binary search to look for the earliest checkpoint taken after `timestamp`.
        //
        // During the loop, the index of the wanted checkpoint remains in the range [low-1, high).
        // With each iteration, `low` or `high` is moved towards the middle of the range to maintain the invariant.
        // - If the middle checkpoint is after `timestamp`, we look in [low, mid)
        // - If the middle checkpoint is before or equal to `timestamp`, we look in [mid+1, high)
        // Once we reach a single value (when low == high), we've found the right checkpoint at the index high-1, if not
        // out of bounds (in which case we're looking too far in the past and the result is 0).
        // Note that if the latest checkpoint available is exactly for `timestamp`, we end up with an index that is
        // past the end of the array, so we technically don't find a checkpoint after `timestamp`, but it works out
        // the same.
        uint256 high = ckpts.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (ckpts[mid].fromTimestamp > timestamp) {
                high = mid;
            } else {
                low = _add(mid, 1);
            }
        }

        return high == 0 ? 0 : ckpts[_subtract(high, 1)].votes;
    }

    /**
     * @dev Delegate votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual override {
        _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Maximum token supply. Defaults to `type(uint224).max` (2^224^ - 1).
     */
    function _maxSupply() internal view virtual returns (uint224) {
        return type(uint224).max;
    }

    /**
     * @dev Snapshots the totalSupply after it has been increased.
     */
    function _mintVotes(address, uint256 amount) internal virtual {
        if (_getTotalSupply() > _maxSupply()) revert TokenVotes__SupplyOverflow();

        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
    }

    /**
     * @dev Snapshots the totalSupply after it has been decreased.
     */
    function _burnVotes(address, uint256 amount) internal virtual {
        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
    }

    function _afterTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        _moveVotingPower(delegates(from), delegates(to), amount);
    }

    /**
     * @dev Change delegation for `delegator` to `delegatee`.
     *
     * Emits events {DelegateChanged} and {DelegateVotesChanged}.
     */
    function _delegate(address delegator, address delegatee) internal virtual {
        address currentDelegate = delegates(delegator);
        uint256 votingPower = _getVotingPower(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveVotingPower(currentDelegate, delegatee, votingPower);
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {DelegateVotesChanged} event.
     */
    function _moveVotingPower(
        address src,
        address dst,
        uint256 amount
    ) private {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                (uint256 oldWeightSrc, uint256 newWeightSrc) = _writeCheckpoint(_checkpoints[src], _subtract, amount);
                emit DelegateVotesChanged(src, oldWeightSrc, newWeightSrc);
            }

            if (dst != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[dst], _add, amount);
                emit DelegateVotesChanged(dst, oldWeight, newWeight);
            }
        }
    }

    function _writeCheckpoint(
        Checkpoint[] storage ckpts,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) private returns (uint256 oldWeight, uint256 newWeight) {
        uint256 pos = ckpts.length;
        oldWeight = pos == 0 ? 0 : ckpts[pos - 1].votes;
        newWeight = op(oldWeight, delta);

        // slither-disable-next-line incorrect-equality
        if (pos > 0 && ckpts[pos - 1].fromTimestamp == block.timestamp) {
            ckpts[pos - 1].votes = SafeCast.toUint224(newWeight);
        } else {
            ckpts.push(
                Checkpoint({fromTimestamp: SafeCast.toUint32(block.timestamp), votes: SafeCast.toUint224(newWeight)})
            );
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }

    // slither-disable-next-line dead-code
    function _getVotingPower(address) internal view virtual returns (uint256);

    // slither-disable-next-line dead-code
    function _getTotalSupply() internal view virtual returns (uint256);
}

