// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IAoriProtocol } from "./IAoriProtocol.sol";
import { AoriProtocol } from "./AoriProtocol.sol";
import { FlashExecutor } from "./FlashExecutor.sol";
import { IERC1271 } from "./IERC1271.sol";

contract AoriVault is IERC1271, FlashExecutor {

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 constant internal ERC1271_MAGICVALUE = 0x1626ba7e;
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public aoriProtocol;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        address _aoriProtocol,
        address _balancerAddress
    ) FlashExecutor(_owner, _balancerAddress) {
        aoriProtocol = _aoriProtocol;
    }

    /*//////////////////////////////////////////////////////////////
                                EIP-1271
    //////////////////////////////////////////////////////////////*/

    function isValidSignature(bytes32 _hash, bytes memory _signature) public view returns (bytes4) {
        require(_signature.length == 65);

        // Deconstruct the signature into v, r, s
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(_signature, 32))
            // second 32 bytes.
            s := mload(add(_signature, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(_signature, 96)))
        }

        address ethSignSigner = ecrecover(_hash, v, r, s);

        // EIP1271 - dangerous if the eip151-eip1271 pairing can be found
        address eip1271Signer = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _hash
                )
            ), v, r, s);

        // check if the signature comes from a valid manager
        if (managers[ethSignSigner] || managers[eip1271Signer]) {
            return ERC1271_MAGICVALUE;
        }

        return 0x0;
    }
}
