// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EnumerableSet.sol";
import "./Ownable2Step.sol";
import "./IFeedOracle.sol";
import "./RrpRequesterV0.sol";
import "./ORMPWrapper.sol";
import "./SubAPIFeed.sol";

/// @title SubAPI
/// @dev The contract uses to serve data feeds of source chain finalized header
/// dAPI security model is the same as edcsa pallet.
/// @notice SubAPI serves data feeds in the form of BeaconSet.
/// The BeaconSet are only updateable using RRPv0.
contract SubAPI is IFeedOracle, RrpRequesterV0, SubAPIFeed, ORMPWrapper, Ownable2Step {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    event SetFee(uint256 indexed fee);
    event AddBeacon(bytes32 indexed beaconId, Beacon beacon);
    event RemoveBeacon(bytes32 indexed beaconId);
    event AirnodeRrpRequested(bytes32 indexed beaconId, bytes32 indexed requestId);
    event AirnodeRrpCompleted(bytes32 indexed beaconId, bytes32 indexed requestId, bytes data);
    event AggregatedORMPData(ORMPData ormpData);

    /// @notice Beacon metadata
    /// @param airnode Airnode address
    /// @param endpointId Endpoint ID
    /// @param sponsor Sponsor address
    /// @param sponsorWallet Sponsor wallet address
    struct Beacon {
        address airnode;
        bytes32 endpointId;
        address sponsor;
        address payable sponsorWallet;
    }

    // name for subAPI
    string public name;
    // fee pay to beacon sponsor wallet address for gas
    uint256 public fee;
    // requestId => beaconId
    mapping(bytes32 => bytes32) private _requestIdToBeaconId;
    // beaconId => requestId
    mapping(bytes32 => bytes32) private _beaconIdToRequestId;
    // beaconIdSet
    EnumerableSet.Bytes32Set private _beaconIds;

    /// @param dao SubAPIDao
    /// @param rrp Airnode RRP contract address
    /// @param ormp ORMP RRP address
    constructor(address dao, address rrp, address ormp) RrpRequesterV0(rrp) ORMPWrapper(ormp) {
        _transferOwnership(dao);
    }

    function setName(string memory name_) external onlyOwner {
        name = name_;
    }

    /// @notice Add a beacon to BeaconSet
    function addBeacon(Beacon calldata beacon) external onlyOwner {
        bytes32 beaconId = deriveBeaconId(beacon);
        require(_beaconIds.add(beaconId), "!add");
        emit AddBeacon(beaconId, beacon);
    }

    /// @notice Remove the beacon from BeaconSet
    function removeBeacon(bytes32 beaconId) external onlyOwner {
        require(_beaconIds.remove(beaconId), "!rm");
        emit RemoveBeacon(beaconId);
    }

    /// @notice change the beacon fee
    function setFee(uint256 fee_) external onlyOwner {
        fee = fee_;
        emit SetFee(fee_);
    }

    function remoteCommitment() external view returns (uint256 count, bytes32 root) {
        count = _aggregatedData.count;
        root = _aggregatedData.root;
    }

    function messageRoot() external view returns (bytes32) {
        return _aggregatedData.root;
    }

    /// @notice Fetch request fee
    /// return tokenAddress if tokenAddress is Address(0x0), pay the native token
    ///        fee the request fee
    function getRequestFee() external view returns (address, uint256) {
        return (address(0), fee * beaconsLength());
    }

    /// @notice Fetch beaconId by requestId
    function getBeaconIdByRequestId(bytes32 requestId) external view returns (bytes32) {
        return _requestIdToBeaconId[requestId];
    }

    /// @notice Fetch requestId by beaconId
    function getRequestIdByBeaconId(bytes32 beaconId) external view returns (bytes32) {
        return _beaconIdToRequestId[beaconId];
    }

    /// @notice BeaconSet length
    function beaconsLength() public view returns (uint256) {
        return _beaconIds.length();
    }

    /// @notice Check if the beacon exist by Id
    function isBeaconExist(bytes32 beaconId) public view returns (bool) {
        return _beaconIds.contains(beaconId);
    }

    /// @notice Derives the Beacon ID from the Airnode address and endpoint ID
    /// @param beacon Beacon
    function deriveBeaconId(Beacon calldata beacon) public pure returns (bytes32 beaconId) {
        beaconId = keccak256(abi.encode(beacon));
    }

    function _request(Beacon calldata beacon, bytes32 beaconId) internal {
        beacon.sponsorWallet.transfer(fee);
        bytes32 requestId = airnodeRrp.makeFullRequest(
            beacon.airnode,
            beacon.endpointId,
            beacon.sponsor,
            beacon.sponsorWallet,
            address(this),
            this.fulfill.selector,
            ""
        );
        _requestIdToBeaconId[requestId] = beaconId;
        _beaconIdToRequestId[beaconId] = requestId;
        emit AirnodeRrpRequested(beaconId, requestId);
    }

    /// @notice Create a request for arbitrum finalized header
    ///         Send reqeust to all beacon in BeaconSet
    function requestFinalizedHash(Beacon[] calldata beacons) external payable {
        uint256 beaconCount = beacons.length;
        require(beaconCount == beaconsLength(), "!all");
        require(msg.value == fee * beaconCount, "!fee");
        for (uint256 i = 0; i < beaconCount; i++) {
            bytes32 beaconId = deriveBeaconId(beacons[i]);
            require(isBeaconExist(beaconId), "!exist");
            _request(beacons[i], beaconId);
        }
    }

    /// @notice  Called by the ArinodeRRP to fulfill the request
    /// @param requestId Request ID
    /// @param data Fulfillment data (`BlockData` encoded in contract ABI)
    function fulfill(bytes32 requestId, bytes calldata data) external onlyAirnodeRrp {
        bytes32 beaconId = _requestIdToBeaconId[requestId];
        require(beaconId != bytes32(0), "!requestId");
        if (_beaconIdToRequestId[beaconId] == requestId) {
            delete _requestIdToBeaconId[requestId];
            delete _beaconIdToRequestId[beaconId];
            _processBeaconUpdate(beaconId, data);
            emit AirnodeRrpCompleted(beaconId, requestId, data);
        } else {
            delete _requestIdToBeaconId[requestId];
        }
    }

    /// @notice Called to aggregate the BeaconSet and save the result.
    ///         beaconIds should be a supermajor(>2/3) subset of all beacons in contract.
    /// @param beaconIds Beacon IDs should be sorted in ascending order
    function aggregateBeacons(bytes32[] calldata beaconIds) external {
        uint256 beaconCount = beaconIds.length;
        bytes32[] memory allBeaconIds = _beaconIds.values();
        require(beaconCount * 3 > allBeaconIds.length * 2, "!supermajor");
        ORMPData[] memory datas = _checkAndGetDatasFromBeacons(beaconIds);
        ORMPData memory data = datas[0];
        for (uint256 i = 1; i < beaconCount; i++) {
            require(eq(data, datas[i]), "!agg");
        }
        require(neq(_aggregatedData, data), "same");
        _aggregatedData = data;
        emit AggregatedORMPData(data);
    }

    function _checkAndGetDatasFromBeacons(bytes32[] calldata beaconIds) internal view returns (ORMPData[] memory) {
        uint256 beaconCount = beaconIds.length;
        ORMPData[] memory datas = new ORMPData[](beaconCount);
        bytes32 last = bytes32(0);
        bytes32 current;
        for (uint256 i = 0; i < beaconCount; i++) {
            current = beaconIds[i];
            require(current > last && isBeaconExist(current), "!beacon");
            datas[i] = _dataFeeds[current];
            last = current;
        }
        return datas;
    }
}

