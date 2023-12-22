// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IZKGame.sol";

abstract contract UserCenter is IUserCenter {
    uint256 private _seasonId;

    uint256 private constant OVERALL_RECORDS_ID = type(uint256).max;

    /** @dev seasonId -> info */
    mapping(uint256 => GameSeason) private _seasons;

    /** @dev seasonId -> user -> statistics */
    mapping(uint256 => mapping(address => PlayerStatistics)) public _seasonLogs;

    function initUserCenter(string memory seasonName) internal {
        _newSeason(seasonName);
    }

    function _newSeason(string memory title) internal {
        _seasons[++_seasonId] = GameSeason(title, block.timestamp);
    }

    function _logGamePlayed(address user) internal {
        _seasonLogs[_seasonId][user].joined++;
        _seasonLogs[OVERALL_RECORDS_ID][user].joined++;
    }

    function _logGameWon(address user) internal {
        _seasonLogs[_seasonId][user].wins++;
        _seasonLogs[OVERALL_RECORDS_ID][user].wins++;
    }

    function userRecords(address user) public view override returns (
        PlayerStatistics memory current,
        PlayerStatistics memory overall
    ) {
        current = _seasonLogs[_seasonId][user];
        overall = _seasonLogs[OVERALL_RECORDS_ID][user];
    }
}

