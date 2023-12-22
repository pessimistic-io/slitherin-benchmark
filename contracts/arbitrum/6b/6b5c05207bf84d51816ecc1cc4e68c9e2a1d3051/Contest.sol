// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Multicall } from "./Multicall.sol";
import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IContestStaker } from "./ContestStaker.sol";
import { IContest } from "./IContest.sol";
import { ConfigStore } from "./ConfigStore.sol";
import { HasConfigStore } from "./HasConfigStore.sol";

// Contest Errors
error HasWinner();
error NoWinner();
error Closed();
error NotClosed();
error EntryNotExists();
error NoStake();
error EntryApproved();
error EntryNotApproved();
error NotEntrant();
error CannotReclaimWinner();
error InvalidMinimumContestTime();
error InvalidApprovedEntryThreshold();

/**
 * @title Contest
 * @notice A Contest lasts for a minimum of 7 days, during which time users can submit entries. The owner can
 * select a winning entry after the 7 days are passed and at least 8 entries have been submitted. The winning entry
 * is minted ERC1155's unique to their entry ID. After 7 days and at least 8 entries have been submitted the contest
 * is closed to new entries.
 * @dev How entries work: In order to submit an entry, a user must stake a designated ERC1155 `stakedContract` in the
 * contest staker contract. By submitting an entry, the user allows this contract to freeze their staked balance
 * in the staker contract until they cancel their entry (or reclaim their losing one). The owner can then approve
 * approve the entry in order for it to be considered for a winning entry and to count towards the
 * "approved entry threshold".
 * @dev What happens to losing entries: Losing entrants can "reclaim" their staked token which instructs this contract
 * to unfreeze their balance in the staker contract. Any user can also can cancel their entry submission if it
 * hasn't been approved as a valid entry yet.
 * @dev What happens to winning entries: The winning entry's staked token is transferred to the beneficiary. The winner
 * is minted a an ERC1155 token with an ID unique to their entry ID.
 */
contract Contest is IContest, HasConfigStore, Ownable, ReentrancyGuard, Multicall {
    // Count of approved entries.
    uint256 public approvedEntries;

    // Timestamp when contest was constructed.
    uint256 public immutable contestStartTime;

    // Conditions that must pass for submission phase to be closed.
    uint256 public immutable minimumContestTime;
    uint256 public immutable approvedEntryThreshold;

    // Counter of submitted entries
    uint256 private _entryId;

    struct Winner {
        uint256 winningId; // entryID of winner
        address winner;
    }

    struct Entry {
        bool isApproved;
        string entryURI;
        address entrant;
        address stakedContract;
        uint256 stakedTokenId;
    }

    Winner public winner;

    mapping(uint256 => Entry) public entries;

    modifier noWinner() {
        if (hasWinner()) {
            revert HasWinner();
        }
        _;
    }

    event SubmittedEntry(
        address indexed stakedContract,
        uint256 indexed stakedTokenId,
        uint256 indexed entryId,
        address entrant,
        string uri
    );
    event AcceptedEntry(uint256 indexed entryId, address indexed entrant);
    event SetWinningEntry(
        uint256 indexed entryId, address winner, address indexed stakedContract, uint256 indexed stakedTokenId
    );
    event CancelledEntry(
        uint256 indexed entryId, address entrant, address indexed stakedContract, uint256 indexed stakedTokenId
    );
    event ReclaimedLosingEntry(
        uint256 indexed entryId, address entrant, address indexed stakedContract, uint256 indexed stakedTokenId
    );

    constructor(
        uint256 _minimumContestTime,
        uint256 _approvedEntryThreshold,
        ConfigStore _configStore
    )
        HasConfigStore(_configStore)
    {
        contestStartTime = block.timestamp;

        if (_minimumContestTime < 600) revert InvalidMinimumContestTime();
        if (_approvedEntryThreshold == 0) revert InvalidApprovedEntryThreshold();
        minimumContestTime = _minimumContestTime;
        approvedEntryThreshold = _approvedEntryThreshold;
    }

    /**
     *
     * Admin functions
     *
     */

    // Once an entry is approved, it cannot be rejected. Skips already approved entries. Entries can't be accepted
    // once a contest is closed but they can be accepted before the contest admin has set a winner.
    function acceptEntries(uint256[] memory entryIds) external override onlyOwner {
        if (isClosed()) revert Closed();
        uint256 newlyAcceptedEntries;
        uint256 len = entryIds.length;
        for (uint32 i; i < len;) {
            if (entries[entryIds[i]].entrant == address(0)) revert EntryNotExists();
            if (!entries[entryIds[i]].isApproved) {
                entries[entryIds[i]].isApproved = true;
                newlyAcceptedEntries++;
                emit AcceptedEntry(entryIds[i], entries[entryIds[i]].entrant);
            }
            unchecked {
                ++i;
            }
        }
        approvedEntries += newlyAcceptedEntries;
    }

    function setWinningEntry(uint256 entryId) external override onlyOwner noWinner nonReentrant {
        if (!isClosed()) revert NotClosed();
        if (entries[entryId].entrant == address(0)) revert EntryNotExists();
        winner = Winner(entryId, entries[entryId].entrant);

        // Send staked token to beneficiary
        IContestStaker(address(_getContestFactory())).transferFrozenStake(
            entries[entryId].stakedContract,
            entries[entryId].stakedTokenId,
            entries[entryId].entrant,
            _getBeneficiary(),
            1
        );
        emit SetWinningEntry(
            entryId, entries[entryId].entrant, entries[entryId].stakedContract, entries[entryId].stakedTokenId
        );
    }

    /**
     *
     * User functions
     *
     */

    // User can choose which Treasure ID `stakedTokenId` to use as their stake provided it os registered in the
    // ContestStaker. The caller must have staked in the contestStaker contract and this function will freeze
    // their balance from being withdrawn in that contract, until the user has either cancelled their
    // unapproved entry or reclaimed their losing entry.
    function submitEntry(
        address stakedContract,
        uint256 stakedTokenId,
        string memory entryURI
    )
        external
        returns (uint256)
    {
        if (isClosed()) revert Closed();
        if (!IContestStaker(address(_getContestFactory())).canUseStake(stakedContract, stakedTokenId, msg.sender)) {
            revert NoStake();
        }
        entries[_entryId] = Entry(false, entryURI, msg.sender, stakedContract, stakedTokenId);
        IContestStaker(address(_getContestFactory())).freezeStake(stakedContract, stakedTokenId, msg.sender, 1);
        emit SubmittedEntry(stakedContract, stakedTokenId, _entryId, msg.sender, entryURI);
        return _entryId++;
    }

    // Can be called as long as an entry is not approved. Unfreezes their stake in contestStaker so user can
    // withdraw. Caller must be entrant.
    function cancelEntry(uint256 entryId) external {
        if (entries[entryId].entrant != msg.sender) revert NotEntrant();
        if (entries[entryId].isApproved) revert EntryApproved();
        address stakedContract = entries[entryId].stakedContract;
        uint256 stakedTokenId = entries[entryId].stakedTokenId;
        delete entries[entryId];
        IContestStaker(address(_getContestFactory())).unfreezeStake(stakedContract, stakedTokenId, msg.sender, 1);
        emit CancelledEntry(entryId, msg.sender, stakedContract, stakedTokenId);
    }

    // When a winner is selected in a contest, all losing entries, except for the winner's entries, will be reclaim
    // their stakes.
    function reclaimEntry(uint256 entryId) external override onlyOwner nonReentrant {
        if (!hasWinner()) revert NoWinner();
        if (entryId == winner.winningId) revert CannotReclaimWinner();
        if (entries[entryId].entrant == address(0)) revert EntryNotExists();
        if (!entries[entryId].isApproved) revert EntryNotApproved();
        address stakedContract = entries[entryId].stakedContract;
        uint256 stakedTokenId = entries[entryId].stakedTokenId;
        IContestStaker(address(_getContestFactory())).unfreezeStake(
            stakedContract, stakedTokenId, entries[entryId].entrant, 1
        );
        emit ReclaimedLosingEntry(entryId, entries[entryId].entrant, stakedContract, stakedTokenId);

        // Don't delete entry as it might be able to be minted again as a losing entry.
    }

    function hasWinner() public view override returns (bool) {
        return winner.winner != address(0);
    }

    function getWinner() external view override returns (address) {
        return winner.winner;
    }

    function getWinningId() external view override returns (uint256) {
        return winner.winningId;
    }

    function getEntrant(uint256 entryId) external view override returns (address) {
        return entries[entryId].entrant;
    }

    // No more entries can be submitted after this threshold is reached. Since approvedEntryThreshold and
    // contest time elapsed are only increasing, once this is true it can reset to false (i.e. this should return
    // false until its true and then always true).
    function isClosed() public view override returns (bool) {
        //slither-disable-next-line timestamp
        return approvedEntries >= approvedEntryThreshold && block.timestamp - contestStartTime >= minimumContestTime;
    }

    function getEntryURI(uint256 entryId) external view override returns (string memory) {
        return entries[entryId].entryURI;
    }
}

