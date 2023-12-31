// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.7;

import "./ICapacitor.sol";
import "./AccessControlExtended.sol";
import "./RescueFundsLib.sol";
import {RESCUE_ROLE} from "./AccessRoles.sol";

abstract contract BaseCapacitor is ICapacitor, AccessControlExtended {
    /// an incrementing id for each new packet created
    uint64 internal _nextPacketCount;
    uint64 internal _nextSealCount;

    address public immutable socket;

    /// maps the packet id with the root hash generated while adding message
    mapping(uint64 => bytes32) internal _roots;

    error NoPendingPacket();
    error OnlySocket();

    modifier onlySocket() {
        if (msg.sender != socket) revert OnlySocket();

        _;
    }

    /**
     * @notice initialises the contract with socket address
     */
    constructor(address socket_, address owner_) AccessControlExtended(owner_) {
        socket = socket_;
    }

    function sealPacket(
        uint256
    ) external virtual override onlySocket returns (bytes32, uint64) {
        uint64 packetCount = _nextSealCount++;
        if (_roots[packetCount] == bytes32(0)) revert NoPendingPacket();

        bytes32 root = _roots[packetCount];
        return (root, packetCount);
    }

    /// returns the latest packet details to be sealed
    /// @inheritdoc ICapacitor
    function getNextPacketToBeSealed()
        external
        view
        virtual
        override
        returns (bytes32, uint64)
    {
        uint64 toSeal = _nextSealCount;
        return (_roots[toSeal], toSeal);
    }

    /// returns the root of packet for given id
    /// @inheritdoc ICapacitor
    function getRootByCount(
        uint64 id_
    ) external view virtual override returns (bytes32) {
        return _roots[id_];
    }

    function getLatestPacketCount() external view returns (uint256) {
        return _nextPacketCount == 0 ? 0 : _nextPacketCount - 1;
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyRole(RESCUE_ROLE) {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

