// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IGameLineup.sol";

abstract contract GameLineup is IGameLineup {
    struct UserRecord {
        uint256 currentLineup;
        uint128 joined;
        uint128 completed;
    }

    struct Lineup {
        address user;
        bytes zkContent;
    }

    uint256 private totalLineupIndex;
    uint256 private endedLineupIndex;
    mapping(uint256 => Lineup) private _lineups;

    mapping(address => UserRecord) private _userRecords;

    // solhint-disable-next-line no-empty-blocks
    function initGameLineup() internal {}

    function lineupUsers() external view override returns(address[] memory list) {
        (
            uint8 counts,
            uint256 from,
            uint256 to
        ) = _lineupCounts();

        list = new address[](counts);

        uint256 cursor = from;
        for (uint256 i = 0; i < counts && cursor <= to; cursor++) {
            if (_lineups[cursor].user != address(0)) list[i++] = _lineups[cursor].user;
        }
    }

    function _lineupCounts() internal view returns (
        uint8 counts,
        uint256 fromIndex,
        uint256 toIndex
    ) {
        fromIndex = endedLineupIndex + 1;

        for (toIndex = fromIndex; toIndex <= totalLineupIndex; toIndex++) {
            if (_lineups[toIndex].user != address(0)) counts++;
        }
    }

    function _userJoinedCounts(address user) internal view returns (uint256) {
        return _userRecords[user].joined;
    }

    function _userInLineup(address user) internal view returns (bool) {
        return _userRecords[user].currentLineup != 0;
    }

    function _joinLineup(
        address user,
        bytes memory zkCard
    ) internal {
        require(!_userInLineup(user), "GameLineup: !allowed");

        Lineup storage lineup = _lineups[++totalLineupIndex];
        lineup.user = user;
        lineup.zkContent = zkCard;

        _userRecords[user].joined++;
        _userRecords[user].currentLineup = totalLineupIndex;

        emit LineupJoined(user);
    }

    function _leaveLineup(address user) internal {
        UserRecord storage userRecord = _userRecords[user];
        require(userRecord.currentLineup != 0, "GameLineUp: !inLineup");

        delete _lineups[userRecord.currentLineup];

        if (endedLineupIndex == userRecord.currentLineup - 1) {
            endedLineupIndex++;
        }

        userRecord.currentLineup = 0;

        emit LineupLeft(user);
    }

    function _completeLineup(uint8 counts) internal returns (Lineup[] memory list) {
        list = new Lineup[](counts);

        for (uint8 completed = 0; completed < counts && endedLineupIndex < totalLineupIndex; ) {
            Lineup storage lineup = _lineups[++endedLineupIndex];

            if (lineup.user != address(0)) {
                list[completed] = lineup;
                _userRecords[lineup.user].completed++;
                _userRecords[lineup.user].currentLineup = 0;

                delete _lineups[endedLineupIndex];

                completed++;
            }
        }
    }
}

