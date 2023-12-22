// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

/// @notice Timestamp implementation of token based voting power and delegation.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/ITokenVotes.sol)
interface ITokenVotes {
    struct Checkpoint {
        uint64 fromTimestamp;
        uint224 votes;
    }

    error TokenVotes__TimeNotPast();
    error TokenVotes__SupplyOverflow();

    /**
     * @dev Emitted when an account changes their delegate.
     */
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /**
     * @dev Emitted when a token transfer or delegate change results in changes to a delegate's number of votes.
     */
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) external view returns (uint256);

    /**
     * @dev Returns the amount of votes that `account` had at the end of a past timestamp (`timestamp`).
     */
    function getPastVotes(address account, uint256 timestamp) external view returns (uint256);

    /**
     * @dev Returns the total supply of votes available at a past timestamp (`timestamp`).
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     */
    function getPastTotalSupply(uint256 timestamp) external view returns (uint256);

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) external view returns (address);

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) external;
}

