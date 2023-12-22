// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {RevenueDistributionToken, IERC20} from "./RevenueDistributionToken.sol";
import {Math} from "./Math.sol";
import {SafeCast} from "./SafeCast.sol";
import {ECDSA} from "./ECDSA.sol";

//                                            j╦
//                                          .╟╫░╦
//                                         ╔╫╫╫░░╦,
//                                        ]╫╫╫╫░░░░╦
//                                      .╫╫╫╫╫╫░░░░░╦.
//                                     ╔╫╫╫╫╫╫╫░░░░░░░U
//                                   .]╫╫╫╫╫╫╫╫░░░░░░░░╦
//                                  ╔╫╫╫╫╫╫╫╫╫╫░░░░░░░░░╦w
//                                 ]╫╫╫╫╫╫╫╫╫╫╫░░░░░░░░░░░N
//                               .╫╫╫╫╫╫╫╫╫╫╫╫╬╬░░░░░░░░░░░╦,
//                              j╫╫╫╫╫╫╫╬╫▓▓▓▓▓▓▓▓▓▓╬╬╦░░░░░╦╦
//                            .]╫╫╬╫▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓╬╬╦░N
//                            ╨╩╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╩╩

//                     ,╗╦╗╗╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╗╗╗╗,
//                    ╔▓▓▓▓▓▓▓▓▓▓╬╬╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╫╬╬╬▓▓▓▓▓▓▓▓▓╗
//                  ,╬▓▓▓▓▓▓▓▓▓▓▓▓▓██▓▓▓▓▄▄╫░╫╫░╫╫╫╬╬╬▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▌.
//                 ╔▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓╦
//                ╗▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓N
//              ╓╣▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓w
//             ╔▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓N
//           ,╣▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▌.
//          ╔▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓╦
//         ║▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓N
//       ╓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓w
//      ╔▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓N
//     ╝▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓M
//        "╨▀▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▀╨"
//             `╙▀▀▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▀╨`
//                  `╙▀▀▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▀▀╨`
//                       `╙▀▀▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▀▀╨`
//                            `╙▀▀▓▓▓▓█████████▓▓▓▓▓▓▓▓▓▓▓▓▓▀╝╙`
//                                 `╙▀▀▓▓██████▓▓▓▓▓▓▓▓▀╩╙`
//                                      `"╨▀▓▓█▓▓▓▀╩"`

//     :::      ::::::::   ::::::::  :::::::::: ::::    :::  :::::::: ::::::::::: ::::::::  ::::    :::
//   :+: :+:   :+:    :+: :+:    :+: :+:        :+:+:   :+: :+:    :+:    :+:    :+:    :+: :+:+:   :+:
//  +:+   +:+  +:+        +:+        +:+        :+:+:+  +:+ +:+           +:+    +:+    +:+ :+:+:+  +:+
// +#++:++#++: +#++:++#++ +#+        +#++:++#   +#+ +:+ +#+ +#++:++#++    +#+    +#+    +:+ +#+ +:+ +#+
// +#+     +#+        +#+ +#+        +#+        +#+  +#+#+#        +#+    +#+    +#+    +#+ +#+  +#+#+#
// #+#     #+# #+#    #+# #+#    #+# #+#        #+#   #+#+# #+#    #+#    #+#    #+#    #+# #+#   #+#+#
// ###     ###  ########   ########  ########## ###    ####  ######## ########### ########  ###    ####
// :::::::::  :::::::::   :::::::: ::::::::::: ::::::::   ::::::::   ::::::::  :::
// :+:    :+: :+:    :+: :+:    :+:    :+:    :+:    :+: :+:    :+: :+:    :+: :+:
// +:+    +:+ +:+    +:+ +:+    +:+    +:+    +:+    +:+ +:+        +:+    +:+ +:+
// +#++:++#+  +#++:++#:  +#+    +:+    +#+    +#+    +:+ +#+        +#+    +:+ +#+
// +#+        +#+    +#+ +#+    +#+    +#+    +#+    +#+ +#+        +#+    +#+ +#+
// #+#        #+#    #+# #+#    #+#    #+#    #+#    #+# #+#    #+# #+#    #+# #+#
// ###        ###    ###  ########     ###     ########   ########   ########  ##########

/// @title Revenue Distribution Token
/// @author Ascension Group
/// @notice Allows token rewards to be distributed linearly over a vesting period.
/// @dev Voting logic borrowed from openzeppelin ERC20Votes.
contract AscensionRevenueDistributionToken is RevenueDistributionToken {
    // =============================================================
    //                       EVENTS
    // =============================================================

    /// @dev Emitted when an account changes their delegate.
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev Emitted when a token transfer or delegate change results in changes to a delegate's number of votes.
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    // =============================================================
    //                       ERRORS
    // =============================================================

    error ExpiredSignature();
    error InvalidNonce();
    error InvalidBlockNumber();
    error VoteOverflow();

    // =============================================================
    //                       CONSTANTS
    // =============================================================

    bytes32 private constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // =============================================================
    //                       STORAGE
    // =============================================================

    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    /// @dev A record of each accounts delegate
    mapping(address => address) private _delegates;

    /// @dev A record of votes checkpoints for each account
    mapping(address => Checkpoint[]) private _checkpoints;

    /// @dev An array of total supply checkpoints
    Checkpoint[] private _totalSupplyCheckpoints;

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    constructor(address initialOwner, IERC20 asset_)
        RevenueDistributionToken(initialOwner, asset_, 1e30, "Ascension Revenue Distribution Token", "xASCEND")
    {}

    // =============================================================
    //                       USER FUNCTIONS
    // =============================================================

    /// @notice Delegate votes from the sender to `delegatee`.
    /// @param delegatee The address to delegate votes to.
    function delegate(address delegatee) external {
        _delegate(msg.sender, delegatee);
    }

    /// @notice Delegates votes from signatory to `delegatee`
    /// @param delegatee The address to delegate votes to.
    /// @param nonce The contract state required to match the signature
    /// @param expiry The time at which to expire the signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        if (block.timestamp > expiry) revert ExpiredSignature();
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry))), v, r, s
        );
        if (nonce != _useNonce(signer)) revert InvalidNonce();
        _delegate(signer, delegatee);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /// @notice Get the `pos`-th checkpoint for `account`.
    /// @param account The address to get the checkpoint for.
    /// @param pos The index of the checkpoint to get.
    /// return The checkpoint at the given index.
    function checkpoints(address account, uint32 pos) public view returns (Checkpoint memory) {
        return _checkpoints[account][pos];
    }

    /// @dev Get number of checkpoints for `account`.
    function numCheckpoints(address account) public view returns (uint32) {
        return SafeCast.toUint32(_checkpoints[account].length);
    }

    /// @notice Get the address `account` is currently delegating to.
    /// @param account The address to get the delegate for.
    /// @return The address `account` is currently delegating to.
    function delegates(address account) public view returns (address) {
        return _delegates[account];
    }

    /// @notice Get the current number of votes for `account`.
    /// @param account The address to get the votes balance.
    /// @return The number of current votes for `account`.
    function getVotes(address account) public view returns (uint256) {
        uint256 pos = _checkpoints[account].length;
        return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
    }

    /// @notice Get the current number of votes for `account`, in terms of the underlying asset.
    /// @param account The address to get the votes balance.
    /// @return The number of current votes for `account`, in terms of the underlying asset.
    function getAssetVotes(address account) public view returns (uint256) {
        return convertToAssets(getVotes(account));
    }

    /// @notice Get the votes for account at the end of `blockNumber`.
    /// @param account The address to get the votes balance.
    /// @param blockNumber The block number to get the vote balance at.
    /// @return The number of votes for `account` at the end of `blockNumber`.
    function getPastVotes(address account, uint256 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert InvalidBlockNumber();
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }

    /// @notice Get the votes for account at the end of `blockNumber`, in terms of the underlying asset.
    /// @dev Converted using the current conversion rate, not the rate at the time of the block.
    /// @param account The address to get the votes balance.
    /// @param blockNumber The block number to get the vote balance at.
    /// @return The number of votes for `account` at the end of `blockNumber`, in terms of the underlying asset.
    function getPastAssetVotes(address account, uint256 blockNumber) public view returns (uint256) {
        return convertToAssets(getPastVotes(account, blockNumber));
    }

    /// @notice Get the current total supply of votes.
    /// @param blockNumber The block number to get the vote balance at.
    /// @return The current total supply of votes.
    function getPastTotalSupply(uint256 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert InvalidBlockNumber();
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    /// @notice Get the current total supply of votes, in terms of the underlying asset.
    /// @dev Converted using the current conversion rate, not the rate at the time of the block.
    /// @param blockNumber The block number to get the vote balance at.
    /// @return The current total supply of votes, in terms of the underlying asset.
    function getPastTotalAssets(uint256 blockNumber) public view returns (uint256) {
        return convertToAssets(getPastTotalSupply(blockNumber));
    }

    // =============================================================
    //                       INTERNAL FUNCTIONS
    // =============================================================

    /// @dev Snapshots the current totalSupply.
    function _mint(address account, uint256 amount) internal override {
        super._mint(account, amount);
        if (totalSupply() > _maxSupply()) revert VoteOverflow();
        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
    }

    /// @dev Snapshots the current totalSupply.
    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);
        if (totalSupply() > _maxSupply()) revert VoteOverflow();
        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
    }

    /// @dev Move voting power when tokens are transferred.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        super._afterTokenTransfer(from, to, amount);
        _moveVotingPower(delegates(from), delegates(to), amount);
    }

    /// @dev Change delegation for `delegator` to `delegatee`.
    function _delegate(address delegator, address delegatee) private {
        address currentDelegate = delegates(delegator);
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveVotingPower(currentDelegate, delegatee, delegatorBalance);
    }

    /// @dev Lookup a votes in a list of (sorted) checkpoints.
    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        // We run a binary search to look for the earliest checkpoint taken after `blockNumber`.
        //
        // Initially we check if the block is recent to narrow the search range.
        // During the loop, the index of the wanted checkpoint remains in the range [low-1, high).
        // With each iteration, either `low` or `high` is moved towards the middle of the range to maintain the invariant.
        // - If the middle checkpoint is after `blockNumber`, we look in [low, mid)
        // - If the middle checkpoint is before or equal to `blockNumber`, we look in [mid+1, high)
        // Once we reach a single votes (when low == high), we've found the right checkpoint at the index high-1, if not
        // out of bounds (in which case we're looking too far in the past and the result is 0).
        // Note that if the latest checkpoint available is exactly for `blockNumber`, we end up with an index that is
        // past the end of the array, so we technically don't find a checkpoint after `blockNumber`, but it works out
        // the same.
        uint256 length = ckpts.length;

        uint256 low = 0;
        uint256 high = length;

        if (length > 5) {
            uint256 mid = length - Math.sqrt(length);
            if (_unsafeAccess(ckpts, mid).fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(ckpts, mid).fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : _unsafeAccess(ckpts, high - 1).votes;
    }

    /// @dev Maximum token supply. Defaults to `type(uint224).max` (2^224^ - 1).
    function _maxSupply() private pure returns (uint224) {
        return type(uint224).max;
    }

    function _moveVotingPower(address src, address dst, uint256 amount) private {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[src], _subtract, amount);
                emit DelegateVotesChanged(src, oldWeight, newWeight);
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

        Checkpoint memory oldCkpt = pos == 0 ? Checkpoint(0, 0) : _unsafeAccess(ckpts, pos - 1);

        oldWeight = oldCkpt.votes;
        newWeight = op(oldWeight, delta);

        if (pos > 0 && oldCkpt.fromBlock == block.number) {
            _unsafeAccess(ckpts, pos - 1).votes = SafeCast.toUint224(newWeight);
        } else {
            ckpts.push(Checkpoint({fromBlock: SafeCast.toUint32(block.number), votes: SafeCast.toUint224(newWeight)}));
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }

    /// @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
    function _unsafeAccess(Checkpoint[] storage ckpts, uint256 pos) private pure returns (Checkpoint storage result) {
        assembly {
            mstore(0, ckpts.slot)
            result.slot := add(keccak256(0, 0x20), pos)
        }
    }
}

