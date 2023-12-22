// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library MetadataRouterStorage {
    // `keccak256(abi.encode(uint256(keccak256("groupos.MetadataRouter")) - 1)) & ~bytes32(uint256(0xff));`
    bytes32 internal constant SLOT = 0xfed67aa0cf3b192df78e3e317c2e0f80e47fc77b946bcf059a08f848f9e4f400;

    struct Layout {
        string defaultURI;
        mapping(string => string) routeURI;
        mapping(string => mapping(address => string)) contractRouteURI;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = SLOT;
        assembly {
            l.slot := slot
        }
    }
}

