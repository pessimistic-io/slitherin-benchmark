// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library AccountGroupStorage {
    // `keccak256(abi.encode(uint256(keccak256("groupos.AccountGroup")) - 1)) & ~bytes32(uint256(0xff));`
    bytes32 internal constant SLOT = 0x39147b94183d90fe4f0d54eaae4f5ad1ed9977a9eea5a3e80ef285bd9a9b9300;

    /// @param defaultInitializer The default initialize controller used to configure ERC6551 accounts on deployment
    /// @param initializerOf Mapping to override the default initialize controller for a subgroupId
    /// @notice ERC6551 accounts may only upgrade to an account approved by the account group
    struct Layout {
        address defaultInitializer;
        mapping(uint64 => address) initializerOf;
        address defaultAccountImplementation;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = SLOT;
        assembly {
            l.slot := slot
        }
    }
}

