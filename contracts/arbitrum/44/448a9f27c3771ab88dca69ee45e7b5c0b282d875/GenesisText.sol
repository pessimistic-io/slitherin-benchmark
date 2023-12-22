// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IContest } from "./IContest.sol";
import { GlobalConstants } from "./Constants.sol";
import { ConfigStore } from "./ConfigStore.sol";
import { Echoes } from "./Echoes.sol";

error ChapterContestNotCreated();
error GenesisEchoContestsDoNotHaveWinner();
error GenesisEchoContestsNotCreated();
error ChapterContestDoesNotHaveWinner();
error PreviousEchoContestsDoNotHaveWinner();
error PreviousChapterContestDoesNotHaveWinner();
error ChapterIdDoesNotExist();

// Genesis texts store a list of chapters which can be mapped to echo contests. This contract keeps track of the latest
// chapter and echo contest that can be opened by the Spire admin. This contract should own
// all of the Echoes contracts in the Spire, so that the admin has to go through this contract to create new echo
// contests, set winner, and approve entries. Similarly, this contract should own all chapter contests.
// The Spire contract should own the Genesis Text contract.
contract GenesisText is Echoes {
    mapping(uint256 => uint256) public nextChapterId;
    mapping(uint256 => uint256) public nextEchoChapterId;

    // The list of Chapters for this Genesis Text. Each Chapter can be mapped to a list of Echo Contests. Each Chapter
    // is also a Contest.
    mapping(uint256 => mapping(uint256 => address)) internal chapterContests;

    event CreatedNextEchoContest(uint256 indexed genesisTextId, uint256 indexed chapterId);
    event CreatedNextChapterContest(
        address indexed nextChapterAddress, uint256 indexed genesisTextId, uint256 indexed chapterId
    );
    event SetChapterContestWinner(
        uint256 indexed genesisTextId,
        uint256 indexed chapterId,
        uint256 indexed winningId,
        address winner,
        uint256 contestWinnerTokenId
    );

    // solhint-disable-next-line no-empty-blocks
    constructor(ConfigStore _configStore, string memory _uri) Echoes(_configStore, _uri) { }

    // This function should be called by Spire when it wants to open a new chapter contest for the genesis text ID.
    function _createNextChapterContest(uint256 genesisTextId) internal {
        // If this is the first chapter contest, then we need to check that the genesis echo contests have set winner.
        if (nextChapterId[genesisTextId] == 0) {
            if (nextEchoChapterId[genesisTextId] == 0) revert GenesisEchoContestsNotCreated();
            if (!_initialEchoContestsHaveWinner(genesisTextId, 0)) revert GenesisEchoContestsDoNotHaveWinner();
        }
        // Otherwise check that the previous chapter's echo contests have winner and that the previous chapter
        // has set a winner.
        else {
            if (!IContest(chapterContests[genesisTextId][nextChapterId[genesisTextId] - 1]).hasWinner()) {
                revert PreviousChapterContestDoesNotHaveWinner();
            }
            if (!_initialEchoContestsHaveWinner(genesisTextId, nextChapterId[genesisTextId])) {
                revert PreviousEchoContestsDoNotHaveWinner();
            }
        }
        uint256 newChapterId = nextChapterId[genesisTextId]++;
        address nextChapterContestAddress = _getContestFactory().deployNewContest(
            GlobalConstants.DEFAULT_CONTEST_MINIMUM_TIME,
            GlobalConstants.DEFAULT_CONTEST_MINIMUM_APPROVED_ENTRIES,
            configStore
        );

        chapterContests[genesisTextId][newChapterId] = nextChapterContestAddress;
        emit CreatedNextChapterContest(nextChapterContestAddress, genesisTextId, newChapterId);
    }

    // This function should be called by Spire when it wants to open a new echoes contest for the genesis text ID.
    function _createNextEchoContests(uint256 genesisTextId) internal {
        // If nextEchoChapterId is 0 then there is a special case where we don't need the chapter contest 0
        // to have closed to create echo contests for the chapter. This is because there is no contest for the first
        // chapter. These echoes are essentially the echoes for the genesis text itself.
        uint256 _nextEchoChapterId = nextEchoChapterId[genesisTextId];
        if (_nextEchoChapterId == 0) {
            nextEchoChapterId[genesisTextId]++;
            emit CreatedNextEchoContest(genesisTextId, _nextEchoChapterId);
            _createInitialEchoContests(
                genesisTextId,
                _nextEchoChapterId,
                GlobalConstants.DEFAULT_CONTEST_MINIMUM_TIME,
                GlobalConstants.DEFAULT_CONTEST_MINIMUM_APPROVED_ENTRIES
            );
        } else {
            // If the next echo chapter ID > 0, then the genesis echoes have been created and we need to now check
            // the next echo chapter ID - 1 (i.e. the "latest echo ID") to see its contest status before proceeding
            // to create new contests.
            uint256 latestEchoId = _latestEchoChapterId(genesisTextId);
            nextEchoChapterId[genesisTextId]++;
            // The chapter contest should be created and must have set a winner before we can open its echoes.
            if (!_hasCreatedChapterContest(genesisTextId, latestEchoId)) {
                revert ChapterContestNotCreated();
            }
            if (!IContest(chapterContests[genesisTextId][latestEchoId]).hasWinner()) {
                revert ChapterContestDoesNotHaveWinner();
            }

            // Link chapter contest with this echo contest.
            // Note: echo contests are 1 ahead of the chapter contest because the genesis echo has the ID 0
            // while the first chapter has ID 1. So to create a new echo we need to create it at the ID + 1.
            emit CreatedNextEchoContest(genesisTextId, latestEchoId + 1);
            _createInitialEchoContests(
                genesisTextId,
                latestEchoId + 1,
                GlobalConstants.DEFAULT_CONTEST_MINIMUM_TIME,
                GlobalConstants.DEFAULT_CONTEST_MINIMUM_APPROVED_ENTRIES
            );
        }
    }

    function _setChapterContestWinner(
        uint256 genesisTextId,
        uint256 chapterId,
        uint256 winnerId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        internal
    {
        if (chapterId >= nextChapterId[genesisTextId]) revert ChapterIdDoesNotExist();
        IContest contest = IContest(chapterContests[genesisTextId][chapterId]);
        contest.setWinningEntry(winnerId);
        address winner = contest.getWinner();
        uint256 contestWinnerTokenId = _mintContestWinner(winner, toBeneficiary);
        _setURI(contestWinnerTokenId, contest.getEntryURI(winnerId));
        uint256 len = losingEntryIds.length;
        for (uint256 i; i < len;) {
            contest.reclaimEntry(losingEntryIds[i]);
            unchecked {
                ++i;
            }
        }

        emit SetChapterContestWinner(genesisTextId, chapterId, winnerId, winner, contestWinnerTokenId);
    }

    function _canCloseLatestChapterContest(uint256 genesisTextId) internal view returns (bool) {
        return IContest(chapterContests[genesisTextId][_latestChapterId(genesisTextId)]).isClosed();
    }

    function _hasCreatedChapterContest(uint256 genesisTextId, uint256 chapterId) internal view returns (bool) {
        return chapterContests[genesisTextId][chapterId] != address(0);
    }

    function _latestChapterId(uint256 genesisTextId) internal view returns (uint256) {
        return nextChapterId[genesisTextId] - 1;
    }

    function _latestEchoChapterId(uint256 genesisTextId) internal view returns (uint256) {
        return nextEchoChapterId[genesisTextId] - 1;
    }
}

