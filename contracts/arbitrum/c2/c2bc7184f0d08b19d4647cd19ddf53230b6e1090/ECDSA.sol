// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

library ECDSA {
    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        // ref. https://ethereum.github.io/yellowpaper/paper.pdf (301) (302)
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "ECDSA: invalid s value in signature"
        );
        require(v == 27 || v == 28, "ECDSA: invalid v value in signature");

        address signer = ecrecover(hash, v, r, s);

        require(signer != address(0), "ECDSA: invalid signature");

        return signer;
    }

    function recover(bytes32 hash, bytes memory sig)
        internal
        pure
        returns (address)
    {
        require(sig.length == 65, "ECDSA: invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }

        return recover(hash, v, r, s);
    }

    function recover(
        bytes32 hash,
        bytes memory sig,
        uint256 index
    ) internal pure returns (address) {
        require(sig.length % 65 == 0, "ECDSA: invalid signature length");
        require(index < sig.length / 65, "ECDSA: invalid signature index");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(add(sig, 0x20), mul(0x41, index)))
            s := mload(add(add(sig, 0x40), mul(0x41, index)))
            v := byte(0, mload(add(add(sig, 0x60), mul(0x41, index))))
        }

        return recover(hash, v, r, s);
    }

    function toEthSignedMessageHash(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }
}

