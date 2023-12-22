// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyCoordinator.sol";

/// @title  PlennyCoordinatorStorage
/// @notice Storage contract for the PlennyCoordinator
abstract contract PlennyCoordinatorStorage is IPlennyCoordinator {

    /// @notice total rewards
    uint256 public totalTimeReward;
    /// @notice number of channels
    uint256 public channelsCount;
    /// @notice number of nodes
    uint256 public nodesCount;
    /// @notice channel threshold, in satoshi
    uint256 public override channelRewardThreshold;
    /// @notice total outbound channel capacity, in satoshi
    uint256 public totalOutboundCapacity;
    /// @notice total inbound channel capacity, in satoshi
    uint256 public totalInboundCapacity;

    /// @notice maps index/id with a channel info
    mapping(uint256 => LightningChannel) public channels;
    /// @notice maps index/id with a node info
    mapping(uint256 => LightningNode) public override nodes;

    /// @dev maps the index for a channel point and the user
    mapping(string => mapping(address => uint256)) internal channelIndexPerId;
    /// @dev confirmed channel points per user
    mapping(string => uint256) internal confirmedChannelIndexPerId;
    /// @notice counter per channel status
    mapping(uint => uint256) public channelStatusCount;
    /// @notice tracks when the reward starts for a given channel
    mapping(uint256 => uint256) public override channelRewardStart;

    /// @dev maps node public key per user and index/id
    mapping(string => mapping(address => uint256)) internal nodeIndexPerPubKey;
    /// @dev node counter per user
    mapping(address => uint256) internal nodeOwnerCount;

    /// @notice nodes per user
    mapping(address => uint256[]) public nodesPerAddress;
    /// @notice channels per user
    mapping(address => uint256[]) public channelsPerAddress;

    struct LightningNode {
        uint256 capacity;
        uint256 addedDate;
        string publicKey;
        address validatorAddress;

        uint256 status;

        uint256 verifiedDate;
        address payable to;
    }

    struct LightningChannel {
        uint256 capacity;
        uint256 appliedDate;
        uint256 confirmedDate;

        uint256 status;

        uint256 closureDate;
        address payable to;
        address payable oracleAddress;
        uint256 rewardAmount;

        uint256 id;
        string channelPoint;
        uint256 blockNumber;
        uint256 blockNumberAlt;
    }

    struct NodeInfo {
        uint256 nodeIndex;
        string ownerPublicKey;
        string validatorPublicKey;
    }

    /// @notice Maximum channel capacity
    uint256 public maximumChannelCapacity;

    /// @notice Minimum channel capacity
    uint256 public minimumChannelCapacity;

    /// @notice Reward baseline
    uint256 public rewardBaseline;
}

