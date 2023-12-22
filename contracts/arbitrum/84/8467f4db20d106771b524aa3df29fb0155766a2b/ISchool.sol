// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct TokenDetails {
    uint128 statAccrued;
    uint64 timestampJoined;
    bool joined;
}

struct StatDetails {
    uint128 globalStatAccrued;
    uint128 emissionRate;
    bool exists;
    bool joinable;
}

interface ISchool {
    function tokenDetails(
        address _collectionAddress,
        uint64 _statId,
        uint256 _tokenId
    ) external view returns (TokenDetails memory);

    function getPendingStatEmissions(
        address _collectionAddress,
        uint64 _statId,
        uint256 _tokenId
    ) external view returns (uint128);

    function statDetails(address _collectionAddress, uint256 _statId)
        external
        view
        returns (StatDetails memory);

    function totalStatsJoinedWithinCollection(
        address _collectionAddress,
        uint256 _tokenId
    ) external view returns (uint256);

    function getTotalStatPlusPendingEmissions(
        address _collectionAddress,
        uint64 _statId,
        uint256 _tokenId
    ) external view returns (uint128);

    function addStatAsAllowedAdjuster(
        address _collectionAddress,
        uint64 _statId,
        uint256 _tokenId,
        uint128 _amountOfStatToAdd
    ) external;

    function removeStatAsAllowedAdjuster(
        address _collectionAddress,
        uint64 _statId,
        uint256 _tokenId,
        uint128 _amountOfStatToRemove
    ) external;
}

