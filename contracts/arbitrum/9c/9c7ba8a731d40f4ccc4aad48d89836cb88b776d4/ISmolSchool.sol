// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISmolSchool {
    /**
     * @dev Joins a stat with a tokenId.
     * @param _collectionAddress collection address token belongs to
     * @param _statId statId to join
     * @param _tokenIds tokens to join stat with
     */
    function joinStat(
        address _collectionAddress,
        uint64 _statId,
        uint256[] memory _tokenIds
    ) external;

    /**
     * @dev Leaves a stat with a tokenId.
     * @param _collectionAddress collection address token belongs to
     * @param _statId statId to leave
     * @param _tokenIds tokens to leave stat with
     */
    function leaveStat(
        address _collectionAddress,
        uint64 _statId,
        uint256[] memory _tokenIds
    ) external;
}

