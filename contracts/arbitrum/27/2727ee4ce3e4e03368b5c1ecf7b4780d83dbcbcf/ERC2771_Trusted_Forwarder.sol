// SPDX-License-Identifier: Commons-Clause-1.0
//  __  __     _        ___     _
// |  \/  |___| |_ __ _| __|_ _| |__
// | |\/| / -_)  _/ _` | _/ _` | '_ \
// |_|  |_\___|\__\__,_|_|\__,_|_.__/
//
// Launch your crypto game or gamefi project's blockchain
// infrastructure & game APIs fast with https://trymetafab.com

pragma solidity ^0.8.16;

import "./ECDSA.sol";
import "./draft-EIP712.sol";
import "./ISystem.sol";
import "./ISystem_Delegate_Approver.sol";

contract ERC2771_Trusted_Forwarder is EIP712 {
  using ECDSA for bytes32;

  struct ForwardRequest {
    address from;
    uint96 nonce;
    address to;
    bytes data;
  }

  bytes32 private constant _TYPEHASH =
    keccak256("ForwardRequest(address from,uint96 nonce,address to,bytes data)");

  // mapping from account to gasless tx nonces to prevent replay
  mapping(address => mapping(uint96 => bool)) private _nonces;

  ISystem_Delegate_Approver immutable systemDelegateApprover;

  constructor(address _systemDelegateApprover) EIP712("ERC2771_Trusted_Forwarder", "1.0.0") {
    systemDelegateApprover = ISystem_Delegate_Approver(_systemDelegateApprover);
  }

  function verify(ForwardRequest calldata req, bytes calldata signature) public view returns (bool) {
    address signer = _hashTypedDataV4(
      keccak256(abi.encode(_TYPEHASH, req.from, req.nonce, req.to, keccak256(req.data)))
    ).recover(signature);

    return !_nonces[req.from][req.nonce] && (signer == req.from || systemDelegateApprover.isDelegateApprovedForSystem(req.from, ISystem(req.to).systemId(), signer));
  }

  function execute(ForwardRequest calldata req, bytes calldata signature) external {
    require(verify(req, signature), "ERC2771_Trusted_Forwarder: signature does not match request, signer is not approved for system, or nonce has been used");

    _nonces[req.from][req.nonce] = true;

    (bool success, bytes memory returnData) = req.to.call(abi.encodePacked(req.data, req.from));

    require(success, string (returnData));
  }
}

