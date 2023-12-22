// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ECDSA.sol";
import "./EIP712.sol";

/**
 * @dev A modified version of OpenZeppelin's MinimalForwarder which can be called only by whitelisted addresses.
 * See "openzeppelin/contracts/metatx/MinimalForwarder.sol" for the original implementation.
 */
contract PrivateForwarder is EIP712, DAOAccessControlled {
    event RelayerApproved(address indexed relayer);
    event RelayerRevoked(address indexed relayer);
    
    using ECDSA for bytes32;

    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    bytes32 private constant _TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    mapping(address => uint256) private _nonces;
    
    mapping(address => bool) private _relayers;

    constructor(address authority)
        EIP712("MinimalForwarder", "0.0.1")
    {
        DAOAccessControlled._setAuthority(authority);
    }

    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    function verify(ForwardRequest calldata req, bytes calldata signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_TYPEHASH, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data)))
        ).recover(signature);
        return _nonces[req.from] == req.nonce && signer == req.from;
    }

    function execute(ForwardRequest calldata req, bytes calldata signature)
        public
        payable
        returns (bool, bytes memory)
    {
        require(_relayers[msg.sender], "Not a relayer");
        require(verify(req, signature), "MinimalForwarder: signature does not match request");
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

    function approveRelayer(address relayer) external onlyGovernor {
        require(!_relayers[relayer], "Already approved");
        _relayers[relayer] = true;

        emit RelayerApproved(relayer);
    }

    function revokeRelayer(address relayer) external onlyGovernor {
        require(_relayers[relayer], "Not a relayer");
        _relayers[relayer] = false;

        emit RelayerRevoked(relayer);
    }
}
