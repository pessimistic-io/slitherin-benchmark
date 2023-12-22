// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library PayoutAddressStorage {
    // `keccak256(abi.encode(uint256(keccak256("groupos.PayoutAddress")) - 1)) & ~bytes32(uint256(0xff));`
    bytes32 internal constant SLOT = 0x6f6b6396a67f685820b27036440227e08d5018166d641c2de98d9ec56a7a9200;

    struct Layout {
        address payoutAddress;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = SLOT;
        assembly {
            l.slot := slot
        }
    }
}

