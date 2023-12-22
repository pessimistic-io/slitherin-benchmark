// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library ERC165Storage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.introspection.storage");

    struct Layout {
        mapping(bytes4 => bool) supportedInterfaces;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function isSupportedInterface(Layout storage l, bytes4 interfaceId) internal view returns (bool) {
        return l.supportedInterfaces[interfaceId];
    }

    function setSupportedInterface(Layout storage l, bytes4 interfaceId, bool status) internal {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        l.supportedInterfaces[interfaceId] = status;
    }
}

