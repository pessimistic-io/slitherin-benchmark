// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyCoordinator {

    function nodes(uint256 index) external view returns (uint256, uint256, string memory, address, uint256, uint256, address payable);

    function openChannel(string memory _channelPoint, address payable _oracleAddress, bool capacityRequest) external;

    function confirmChannelOpening(uint256 channelIndex, uint256 _channelCapacitySat,
        uint256 channelId, string memory node1PublicKey, string memory node2PublicKey) external;

    function verifyDefaultNode(string calldata publicKey, address payable account) external returns (uint256);

    function closeChannel(uint256 channelIndex) external;

    function channelRewardStart(uint256 index) external view returns (uint256);

    function channelRewardThreshold() external view returns (uint256);
}
