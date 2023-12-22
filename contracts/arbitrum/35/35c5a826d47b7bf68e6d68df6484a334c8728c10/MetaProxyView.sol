// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

library MetaProxyView {
    function computeBytecodeHash(
        address targetContract,
        bytes memory metadata
    ) internal pure returns (bytes32 bytecodeHash) {
        uint256 offset;
        uint256 length = metadata.length;
        assembly {
            offset := add(metadata, 32)

            // load free memory pointer as per solidity convention
            let start := mload(64)
            // keep a copy
            let ptr := start
            // deploy code (11 bytes) + first part of the proxy (21 bytes)
            mstore(
                ptr,
                0x600b380380600b3d393df3363d3d373d3d3d3d60368038038091363936013d73
            )
            ptr := add(ptr, 32)

            // store the address of the contract to be called
            mstore(ptr, shl(96, targetContract))
            // 20 bytes
            ptr := add(ptr, 20)

            // the remaining proxy code...
            mstore(
                ptr,
                0x5af43d3d93803e603457fd5bf300000000000000000000000000000000000000
            )
            // ...13 bytes
            ptr := add(ptr, 13)

            // copy the metadata
            {
                for {
                    let i := 0
                } lt(i, length) {
                    i := add(i, 32)
                } {
                    mstore(add(ptr, i), mload(add(offset, i)))
                }
            }
            ptr := add(ptr, length)
            // store the size of the metadata at the end of the bytecode
            mstore(ptr, length)
            ptr := add(ptr, 32)

            // The size is deploy code + contract code + calldatasize - 4 + 32.
            bytecodeHash := keccak256(start, sub(ptr, start))
        }
    }
}

