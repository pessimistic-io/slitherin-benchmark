// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

struct RelayEntry {
    address relayAddress;
    string url;
    uint256 priority;
}

interface IRelayStore {
    event RelayPercentageChanged(uint8 newRelayPercentage);
    event RelayPercentageSwapChanged(uint8 newRelayPercentageSwap);
    event RelayAddedOrSet(address relayAddress, string url, uint256 priority);

    function setRelayPercentage(uint8 _relayPercentage) external;

    function setRelayPercentageSwap(uint8 _relayPercentageSwap) external;

    function isRelayInList(address relay) external returns (bool);

    function getRelayList() external view returns (RelayEntry[] memory);

    function addOrSetRelay(
        address relayAddress,
        string memory url,
        uint256 priority
    ) external;

    function relayPercentage() external view returns (uint8);

    function relayPercentageSwap() external view returns (uint8);
    // function swapSlippagePercentage() external view returns (uint8);
}

