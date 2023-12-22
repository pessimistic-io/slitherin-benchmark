// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inspired by the following contract: https://github.com/OpenBazaar/smart-contracts/blob/22d3f190163102f9ceee95ac705001c82ca55624/contracts/registry/ContractManager.sol

import {Address} from "./Address.sol";

import {FsUtils} from "./FsUtils.sol";
import {ImmutableGovernance} from "./ImmutableGovernance.sol";
import {ImmutableVersion} from "./ImmutableVersion.sol";
import {IVersionManager} from "./IVersionManager.sol";

import {Errors} from "./Errors.sol";

/// @title Supa Version Manager
contract VersionManager is IVersionManager, ImmutableGovernance {
    /// @dev Array of all version names
    string[] internal _versionString;

    /// @dev Mapping from version names to version structs
    mapping(string => Version) internal _versions;

    /// @dev The recommended version
    string internal _recommendedVersion;

    modifier versionExists(string memory versionName) {
        if (_versions[versionName].implementation == address(0)) {
            revert Errors.VersionNotRegistered();
        }
        _;
    }

    modifier validStatus(Status status) {
        if (uint8(status) > uint8(Status.DEPRECATED)) {
            revert Errors.InvalidStatus();
        }
        _;
    }

    modifier validBugLevel(BugLevel bugLevel) {
        if (uint8(bugLevel) > uint8(BugLevel.CRITICAL)) {
            revert Errors.InvalidBugLevel();
        }
        _;
    }

    constructor(address _owner) ImmutableGovernance(_owner) {}

    /// @inheritdoc IVersionManager
    function addVersion(
        Status status,
        address _implementation
    ) external onlyGovernance validStatus(status) {
        address implementation = FsUtils.nonNull(_implementation);
        // implementation must be a contract
        if (!Address.isContract(implementation)) {
            revert Errors.InvalidImplementation();
        }

        string memory versionName = "";
        try ImmutableVersion(implementation).immutableVersion() returns (bytes32 immutableVersion) {
            versionName = string(FsUtils.decodeFromBytes32(immutableVersion));
        } catch {
            revert Errors.InvalidImplementation();
        }

        // version name must not be the empty string
        if (bytes(versionName).length == 0) {
            revert Errors.InvalidVersionName();
        }

        // the version name should not already be registered
        if (_versions[versionName].implementation != address(0)) {
            revert Errors.VersionAlreadyRegistered();
        }
        _versionString.push(versionName);

        _versions[versionName] = Version({
            versionName: versionName,
            status: status,
            bugLevel: BugLevel.NONE,
            implementation: implementation,
            dateAdded: block.timestamp
        });

        emit VersionAdded(versionName, implementation);
    }

    /// @inheritdoc IVersionManager
    function updateVersion(
        string calldata versionName,
        Status status,
        BugLevel bugLevel
    )
        external
        onlyGovernance
        versionExists(versionName)
        validStatus(status)
        validBugLevel(bugLevel)
    {
        _versions[versionName].status = status;
        _versions[versionName].bugLevel = bugLevel;

        emit VersionUpdated(versionName, status, bugLevel);
    }

    /// @inheritdoc IVersionManager
    function markRecommendedVersion(
        string calldata versionName
    ) external onlyGovernance versionExists(versionName) {
        if (
            _versions[versionName].status == IVersionManager.Status.DEPRECATED ||
            _versions[versionName].bugLevel != IVersionManager.BugLevel.NONE
        ) {
            revert Errors.InvalidVersion();
        }
        // set the version name as the recommended version
        _recommendedVersion = versionName;

        emit VersionRecommended(versionName);
    }

    /// @inheritdoc IVersionManager
    function removeRecommendedVersion() external onlyGovernance {
        // delete the recommended version name
        delete _recommendedVersion;

        emit RecommendedVersionRemoved();
    }

    /// @inheritdoc IVersionManager
    function getRecommendedVersion()
        external
        view
        returns (
            string memory versionName,
            Status status,
            BugLevel bugLevel,
            address implementation,
            uint256 dateAdded
        )
    {
        if (bytes(_recommendedVersion).length == 0) {
            revert Errors.NoRecommendedVersion();
        }
        versionName = _recommendedVersion;

        Version storage recommendedVersion = _versions[versionName];

        status = recommendedVersion.status;
        bugLevel = recommendedVersion.bugLevel;
        implementation = recommendedVersion.implementation;
        dateAdded = recommendedVersion.dateAdded;

        return (versionName, status, bugLevel, implementation, dateAdded);
    }

    /// @inheritdoc IVersionManager
    function getVersionCount() external view returns (uint256 count) {
        count = _versionString.length;
    }

    /// @inheritdoc IVersionManager
    function getVersionAtIndex(uint256 index) external view returns (string memory versionName) {
        versionName = _versionString[index];
    }

    /// @inheritdoc IVersionManager
    function getVersionAddress(uint256 index) external view returns (address) {
        string memory versionName = _versionString[index];
        Version memory v = _versions[versionName];
        return v.implementation;
    }

    /// @inheritdoc IVersionManager
    function getVersionDetails(
        string calldata versionName
    )
        external
        view
        returns (
            string memory versionString,
            Status status,
            BugLevel bugLevel,
            address implementation,
            uint256 dateAdded
        )
    {
        Version storage v = _versions[versionName];

        versionString = v.versionName;
        status = v.status;
        bugLevel = v.bugLevel;
        implementation = v.implementation;
        dateAdded = v.dateAdded;

        return (versionString, status, bugLevel, implementation, dateAdded);
    }
}

