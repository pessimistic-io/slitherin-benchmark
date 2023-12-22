// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title OnboardingRequest
 * @dev Interface for the DAO OnboardingRequest.
 */
interface IOnboardingRequest {
    /**
     * @notice Event emitted when a new request is added.
     * @param sender Address of the sender adding the request.
     * @param gov Address of the associated government.
     * @param index Index assigned to the request.
     */
    event AddedRequest(
        address indexed sender,
        address indexed gov,
        uint128 index
    );

    /**
     * @notice Event emitted when an existing request is removed.
     * @param gov Address of the associated government.
     * @param index Index of the removed request.
     */
    event RemovedRequest(
        address indexed gov,
        uint128 indexed index
    );

    /**
     * @notice Struct representing an onboarding request.
     * @param sender Address of the sender creating the request.
     * @param timelock Address of the associated timelock.
     * @param tokenApproved Address of the approved token for the request.
     * @param amountApproved Approved amount of the token for the request.
     * @param requestedMint Requested amount for minting.
     * @param timestamp Timestamp of the request creation.
     */
    struct Request {
        address sender;
        address timelock;
        address tokenApproved;
        uint256 amountApproved;
        uint256 requestedMint;
        uint256 timestamp;
    }

    /**
     * @notice Adds a new onboarding request.
     * @param _gov Address of the associated government.
     * @param _timelock Address of the associated timelock.
     * @param _tokenApproved Address of the approved token for the request.
     * @param _amountApproved Approved amount of the token for the request.
     * @param _requestedMint Requested amount for minting.
     */
    function addRequest(
        address _gov,
        address _timelock,
        address _tokenApproved,
        uint256 _amountApproved,
        uint256 _requestedMint
    ) external;

    /**
     * @notice Removes an existing onboarding request. Only the associated timelock can remove a request.
     * @param _gov Address of the associated government.
     * @param _index Index of the request to be removed.
     */
    function removeRequest(address _gov, uint128 _index) external;
}

