// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyOcean.sol";

 /// @title PlennyOceanStorage
 /// @dev   Storage contract for PlennyOcean
abstract contract PlennyOceanStorage is IPlennyOcean {

    /// @notice capacity requests mapping
    mapping (uint256 => LightningCapacityRequest) public override capacityRequests;
    /// @notice list of makers
    mapping (uint256 => MakerInfo) public makers;

    /// @notice maker id per address
    mapping(address => uint256)public override makerIndexPerAddress;
    /// @notice liquidity request per channel opened
    mapping(string => uint256) public override capacityRequestPerChannel;
    /// @notice liquidity requests per maker
    mapping(address => uint256[]) public capacityRequestPerMaker;
    /// @notice liquidity requests per taker
    mapping(address => uint256[]) public capacityRequestPerTaker;

    /// @dev nonce seen in the signatures signed by the taker
    mapping(address => mapping(uint256 => bool)) internal seenNonces;

    struct MakerInfo {
        string makerName;
        string makerServiceUrl;
        address makerAddress;
        uint256 makerNodeIndex;
        uint256 makerProvidingAmount;
        uint256 makerRatePl2Sat;
    }

    struct LightningCapacityRequest {
        uint256 capacity;
        uint256 addedDate;

        string nodeUrl;
        address payable makerAddress;

        uint256 status;

        uint256 plennyReward;
        string channelPoint;
        address payable to;
    }

    /// @notice cancelling block period
    uint256 public cancelingRequestPeriod;
    /// @notice one-reward given for the maker when the channel is opened, to cover for the channel opening costs.
    uint256 public makerCapacityOneTimeReward;
    /// @notice fee charged to the maker reward
    uint256 public makerRewardFee;
    /// @notice fee charged to the taker for requesting its liquidity
    uint256 public takerFee;
    /// @notice number of liquidity requests
    uint256 public override capacityRequestsCount;
    /// @notice number of makers
    uint256 public makersCount;
    /// @notice number of takers
    uint256 public takersCount;
}

