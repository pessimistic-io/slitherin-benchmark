// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVersionManager {
    /// @dev Signifies the status of a version
    enum Status {
        BETA,
        RC,
        PRODUCTION,
        DEPRECATED
    }

    /// @dev Indicated the highest level of bug found in the version
    enum BugLevel {
        NONE,
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    /// @dev A struct to encode version details
    struct Version {
        // the version number string ex. "v1.0"
        string versionName;
        Status status;
        BugLevel bugLevel;
        // the address of the instantiation of the version
        address implementation;
        // the date when this version was registered with the contract
        uint256 dateAdded;
    }

    event VersionAdded(string versionName, address indexed implementation);

    event VersionUpdated(string versionName, Status status, BugLevel bugLevel);

    event VersionRecommended(string versionName);

    event RecommendedVersionRemoved();

    /// @notice Registers a new version of the store contract
    /// @param status Status of the version to be added
    /// @param _implementation The address of the implementation of the version
    function addVersion(Status status, address _implementation) external;

    /// @notice Update a contract version
    /// @param versionName Version of the contract
    /// @param status Status of the contract
    /// @param bugLevel New bug level for the contract
    function updateVersion(string calldata versionName, Status status, BugLevel bugLevel) external;

    /// @notice Set the recommended version
    /// @param versionName Version of the contract
    function markRecommendedVersion(string calldata versionName) external;

    /// @notice Remove the recommended version
    function removeRecommendedVersion() external;

    /// @notice Get recommended version for the contract.
    /// @return versionName The name of the recommended version
    /// @return status The status of the recommended version
    /// @return bugLevel The bug level of the recommended version
    /// @return implementation The address of the implementation of the recommended version
    /// @return dateAdded The date the recommended version was added
    function getRecommendedVersion()
        external
        view
        returns (
            string memory versionName,
            Status status,
            BugLevel bugLevel,
            address implementation,
            uint256 dateAdded
        );

    /// @notice Get total count of versions
    function getVersionCount() external view returns (uint256 count);

    /// @dev Returns the version name at specific index in the versionString[] array
    /// @param index The index to be searched for
    function getVersionAtIndex(uint256 index) external view returns (string memory versionName);

    /// @notice Get the implementation address for a version
    /// @param index The index of the version
    function getVersionAddress(uint256 index) external view returns (address);

    /// @notice Returns the version details for the given version name
    /// @param versionName Version string
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
        );
}

