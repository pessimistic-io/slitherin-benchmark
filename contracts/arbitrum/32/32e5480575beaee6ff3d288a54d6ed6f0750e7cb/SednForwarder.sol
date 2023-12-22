// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ECDSA.sol";
import "./EIP712Adapted.sol";

/**
 * @dev Simple minimal forwarder to be used together with an ERC2771 compatible contract. See {ERC2771Context}.
 * @notice EIP712 adapted to omit chainid, chainid checked as part of message
 * 
 * MinimalForwarder is mainly meant for testing, as it is missing features to be a good production-ready forwarder. This
 * contract does not intend to have all the properties that are needed for a sound forwarding system. A fully
 * functioning forwarding system with good properties requires more complexity. We suggest you look at other projects
 * such as the GSN which do have the goal of building a system like that.
 */
contract SednForwarder is EIP712Adapted {
    using ECDSA for bytes32;

    struct ForwardRequest {
        address from;
        address to;
        uint256 chainid; 
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 valid;
    }

    bytes32 private constant _TYPEHASH =
        keccak256(
            "ForwardRequest(address from,address to,uint256 chainid"
            ",uint256 value,uint256 gas,uint256 nonce,uint256 valid,bytes data)"
            );

    mapping(address => uint256) private _nonces;

    constructor() EIP712Adapted("SednForwarder", "0.0.2") {}

    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    function verify(ForwardRequest calldata req, bytes calldata signature) public view returns (bool) {
        require(req.valid == 0 || req.valid > block.timestamp, "SednForwarder: request expired");
        require(req.chainid == block.chainid, "SednForwarder: wrong chain id");
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                _TYPEHASH, req.from, req.to, req.chainid, req.value, req.gas, req.nonce, req.valid, keccak256(req.data)
                )
            )
        ).recover(signature);
        return _nonces[req.from] == req.nonce && signer == req.from;
    }

    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public payable returns (bool, bytes memory) {
        require(verify(req, signature), "SednForwarder: signature does not match request");
        _nonces[req.from] = req.nonce + 1;

        (bool success, bytes memory returndata) = req.to.call{gas: req.gas, value: req.value}(
            abi.encodePacked(req.data, req.from)
        );

        // Validate that the relayer has sent enough gas for the call.
        // See https://ronan.eth.limo/blog/ethereum-gas-dangers/
        if (gasleft() <= req.gas / 63) {
            // We explicitly trigger invalid opcode to consume all gas and bubble-up the effects, since
            // neither revert or assert consume all gas since Solidity 0.8.0
            // https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }

        return (success, returndata);
    }
}
