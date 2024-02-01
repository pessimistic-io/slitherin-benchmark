// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./EIP712.sol";

contract VerifySigEIP712 is EIP712("EtherMail", "1") {
    address[] public ownerList;

    uint256 constant chainId = 137; //  Change it to suit your network.

    struct Input {
        uint256 ToTokenChainId;
        address FromTokenAddress;
        address ToTokenAddress;
        address VaultContract;
        uint256 Amount;
        uint256 Slippage;
        address UserAddress;
    }

    bytes32 private constant SWAP_TYPEHASH =
        keccak256(
            "Input(uint256 ToTokenChainId,address FromTokenAddress,address ToTokenAddress,address VaultContract,uint256 Amount,uint256 Slippage,address UserAddress)"
        );

    function setOwenr(address[] memory _owner) public {
        for (uint256 i = 0; i < _owner.length; i++) {
            ownerList.push(_owner[i]);
        }
    }

    function relaySig(Input memory _swapData, bytes[] memory signature)
        public
        view
        returns (bool)
    {
        uint256 CheckCount;
        Input memory inputData = _swapData;

        for (uint256 i = 0; i < signature.length; i++) {
            bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        SWAP_TYPEHASH,
                        inputData.ToTokenChainId,
                        inputData.FromTokenAddress,
                        inputData.ToTokenAddress,
                        inputData.VaultContract,
                        inputData.Amount,
                        inputData.Slippage,
                        inputData.UserAddress
                    )
                )
            );
            (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature[i]);
            address signer = ECDSA.recover(digest, v, r, s);

            if (signer == ownerList[i]) {
                CheckCount++;
            }
        }
        if (CheckCount == signature.length) return true;
        else {
            revert("not match");
        }
    }

    // 시그니쳐 넣으면 r s v 찢어주는 함수
    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");
        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }
}

