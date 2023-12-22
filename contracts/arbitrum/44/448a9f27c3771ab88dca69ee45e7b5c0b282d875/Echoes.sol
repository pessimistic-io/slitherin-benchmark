// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ERC1155Supply, ERC1155 } from "./ERC1155Supply.sol";
import { IContest } from "./IContest.sol";
import { GlobalConstants } from "./Constants.sol";
import { ConfigStore } from "./ConfigStore.sol";
import { HasConfigStore } from "./HasConfigStore.sol";

// Echoes is designed to be extended by the GenesisText contract to give it access to a set of Echo contests that
// are unique to each chapter ID and Genesis Text ID. This contract provides helper functions to set Echo contest
// winner, create new contests, and approve entries for contests. The Spire contract needs to know when to move
// on to the next Chapter and Echo contest and it therefore must know when echo contests are closed for a given
// chapter. They are considered closed when *all* echo contests for a chapter are closed, so this contract provides
// helper functions to read the state of all echo contests for a given chapter.
error InitialEchoContestsDoNotHaveWinner();
error InvalidAdditionalEchoContestCount();
error AlreadyIntializedEchoes();

contract Echoes is HasConfigStore, ERC1155Supply {
    // Keeps track of ERC1155 Token Id
    // Changes for each subsequent contest
    uint256 public nextContestWinnerId;

    // SPIR-160 Changes
    // tokenId -> uri
    mapping(uint256 => string) public contestURI;

    // Mapping of Genesis Text ID to Chapter ID to Echo contest identified by unique ID.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => address))) public chapterEchoes;
    mapping(uint256 => mapping(uint256 => uint256)) public echoCount;

    event CreatedEchoContest(
        uint256 genesisTextId,
        uint256 indexed chapterId,
        uint256 indexed echoId,
        uint256 minimumContestTime,
        uint256 approvedEntryThreshold,
        address indexed echoContestAddress
    );

    event SetEchoContestWinner(
        uint256 indexed genesisTextId,
        uint256 indexed chapterId,
        uint256 echoId,
        uint256 indexed winningId,
        address winner,
        uint256 contestWinnerTokenId
    );

    event MintContestReward(uint256 indexed contestRewardTokenId, address indexed recipient, uint256 indexed amount);

    constructor(ConfigStore _configStore, string memory _uri) HasConfigStore(_configStore) ERC1155(_uri) {
        // solhint-disable-previous-line no-empty-blocks
    }

    // Don't call uri(), it will return the default URI
    // Call this function by passing the specific tokenId
    function _getURI(uint256 tokenId) internal view returns (string memory) {
        return contestURI[tokenId];
    }

    // Internal function given admin accessibility in parent contracts
    function _setURI(uint256 tokenId, string memory uri) internal {
        contestURI[tokenId] = uri;
        emit URI(uri, tokenId);
    }

    function _mintContestWinner(address winner, bool toBeneficiary) internal returns (uint256 contestRewardTokenId) {
        contestRewardTokenId = nextContestWinnerId++;
        uint256 _teamCount = GlobalConstants.CONTEST_REWARD_AMOUNT * _getTeamPercent() / (100);
        if (toBeneficiary) {
            _mint(_getBeneficiary(), contestRewardTokenId, GlobalConstants.CONTEST_REWARD_AMOUNT - _teamCount, "");
        } else {
            _mint(winner, contestRewardTokenId, GlobalConstants.CONTEST_REWARD_AMOUNT - _teamCount, "");
        }
        _mint(_getTeamWallet(), contestRewardTokenId, _teamCount, "");
        emit MintContestReward(contestRewardTokenId, winner, GlobalConstants.CONTEST_REWARD_AMOUNT - _teamCount);
    }

    // Internal function only for token minted of genensis text.
    function _mintContestWinnerBatch(address winner, uint256 count) internal {
        uint256 contestRewardTokenId = nextContestWinnerId;
        for (uint256 i; i < count;) {
            _mint(winner, contestRewardTokenId + i, GlobalConstants.CONTEST_REWARD_AMOUNT, "");
            emit MintContestReward(contestRewardTokenId + i, winner, GlobalConstants.CONTEST_REWARD_AMOUNT);
            unchecked {
                ++i;
            }
        }
        nextContestWinnerId += count;
    }

    // Create `contestCount` new Echo contests. This method will only succeed once and create INITIAL_ECHO_COUNT
    // echoes at once.
    function _createInitialEchoContests(
        uint256 genesisTextId,
        uint256 chapterId,
        uint256 minimumContestTime,
        uint256 approvedEntryThreshold
    )
        internal
    {
        if (echoCount[genesisTextId][chapterId] != 0) revert AlreadyIntializedEchoes();
        for (uint256 i; i < GlobalConstants.INITIAL_ECHO_COUNT;) {
            _createEchoContest(genesisTextId, chapterId, minimumContestTime, approvedEntryThreshold);
            unchecked {
                ++i;
            }
        }
    }

    // Approve entryIds for echo ID.
    function _approveEchoContestEntries(
        uint256 genesisTextId,
        uint256 chapterId,
        uint256 echoId,
        uint256[] memory entryIds
    )
        internal
    {
        IContest(chapterEchoes[genesisTextId][chapterId][echoId]).acceptEntries(entryIds);
    }

    function _createEchoContest(
        uint256 genesisTextId,
        uint256 chapterId,
        uint256 minimumContestTime,
        uint256 approvedEntryThreshold
    )
        private
    {
        uint256 nextEchoId = echoCount[genesisTextId][chapterId];
        echoCount[genesisTextId][chapterId]++;
        address echoContestAddress =
            _getContestFactory().deployNewContest(minimumContestTime, approvedEntryThreshold, configStore);
        chapterEchoes[genesisTextId][chapterId][nextEchoId] = echoContestAddress;
        emit CreatedEchoContest(
            genesisTextId, chapterId, nextEchoId, minimumContestTime, approvedEntryThreshold, echoContestAddress
        );
    }

    // This can be used to set winner of echo contests.
    function _setEchoContestWinner(
        uint256 genesisTextId,
        uint256 chapterId,
        uint256 contestId,
        uint256 entryId,
        uint256[] memory losingEntryIds,
        bool toBeneficiary
    )
        internal
    {
        IContest echoContest = IContest(chapterEchoes[genesisTextId][chapterId][contestId]);
        if (echoContest.hasWinner() || !echoContest.isClosed()) return;
        echoContest.setWinningEntry(entryId);
        address winner = echoContest.getWinner();
        uint256 contestWinnerTokenId = _mintContestWinner(winner, toBeneficiary);
        _setURI(contestWinnerTokenId, echoContest.getEntryURI(entryId));
        uint256 len = losingEntryIds.length;
        for (uint256 i; i < len;) {
            echoContest.reclaimEntry(losingEntryIds[i]);
            unchecked {
                ++i;
            }
        }
        emit SetEchoContestWinner(genesisTextId, chapterId, contestId, entryId, winner, contestWinnerTokenId);
    }

    function _initialEchoContestsClosed(uint256 genesisTextId, uint256 chapterId) internal view returns (bool) {
        for (uint256 i; i < GlobalConstants.INITIAL_ECHO_COUNT;) {
            if (!IContest(chapterEchoes[genesisTextId][chapterId][i]).isClosed()) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    function _initialEchoContestsHaveWinner(uint256 genesisTextId, uint256 chapterId) internal view returns (bool) {
        if (chapterEchoes[genesisTextId][chapterId][0] == address(0)) {
            return false;
        }

        for (uint256 i; i < GlobalConstants.INITIAL_ECHO_COUNT;) {
            if (!IContest(chapterEchoes[genesisTextId][chapterId][i]).hasWinner()) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }
}

