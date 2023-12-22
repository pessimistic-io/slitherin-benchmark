// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyOcean {

    function processCapacityRequest(uint256 index) external;

    function closeCapacityRequest(uint256 index, uint256 id, uint256 date) external;

    function collectCapacityRequestReward(uint256 index, uint256 id, uint256 date) external;

    function capacityRequests(uint256 index) external view returns (uint256, uint256, string memory, address payable,
        uint256, uint256, string memory, address payable);

    function capacityRequestPerChannel(string calldata channelPoint) external view returns (uint256 index);

    function makerIndexPerAddress(address addr) external view returns (uint256 index);

    function capacityRequestsCount() external view returns (uint256);

}
