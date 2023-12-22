// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

interface ISwitchboard {
    function registerCapacitor(
        uint256 siblingChainSlug_,
        address capacitor_,
        uint256 maxPacketSize_
    ) external;

    function allowPacket(
        bytes32 root,
        bytes32 packetId,
        uint32 srcChainSlug,
        uint256 proposeTime
    ) external view returns (bool);

    function getMinFees(
        uint32 dstChainSlug_
    ) external view returns (uint256, uint256);
}

