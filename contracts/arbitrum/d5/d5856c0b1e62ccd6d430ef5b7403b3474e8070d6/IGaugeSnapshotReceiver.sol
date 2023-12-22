pragma solidity ^0.8.6;

interface IGaugeSnapshotReceiver {
    struct Snapshot {
        address gaugeAddress;
        uint256 timestamp;
        uint256 inflationRate;
        uint256 workingSupply;
        uint256 virtualPrice;
        uint256 relativeWeight;
    }

    function snapshots(address, uint256) external view returns(Snapshot memory);

    function getSnapshots(address _address) external view returns (Snapshot[] memory);

    function getSnapshotsLength(address _address) external view returns(uint256);
}
