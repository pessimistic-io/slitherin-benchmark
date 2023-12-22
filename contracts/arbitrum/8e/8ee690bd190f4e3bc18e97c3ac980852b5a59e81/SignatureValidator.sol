// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./verification_Auth.sol";
import "./IFabricator.sol";

contract SignatureValidator is Auth {
  struct EIP712Domain {
    string name;
    string version;
    uint256 chainId;
    address verifyingContract;
  }

  struct Target {
    uint256 chainId;
    uint256 tokenId;
    address wallet;
    uint256 amount;
  }
  IFabricator public core;

  event SignerSet(address newSigner);

  using ECDSA for bytes32;

  bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
    keccak256(
      "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

  bytes32 private constant _TARGET_TYPEHASH =
    keccak256(
      "Target(uint256 chainId,uint256 cycle,address wallet,uint256 amount)"
    );

  bytes32 private immutable _domainSeparator;

  address public validationSigner;

  constructor(
    address signer,
    IFabricator _core,
    Authority authority
  ) Auth(msg.sender, authority) {
    validationSigner = signer;
    core = _core;
    _domainSeparator = _hashDomain(
      EIP712Domain({
        name: "SYNTH Validator",
        version: "1",
        chainId: _getChainID(),
        verifyingContract: address(this)
      })
    );
  }

  function _hashDomain(EIP712Domain memory eip712Domain)
    private
    pure
    returns (bytes32)
  {
    return
      keccak256(
        abi.encode(
          _EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(eip712Domain.name)),
          keccak256(bytes(eip712Domain.version)),
          eip712Domain.chainId,
          eip712Domain.verifyingContract
        )
      );
  }

  function _hashRecipient(Target memory recipient)
    private
    pure
    returns (bytes32)
  {
    return
      keccak256(
        abi.encode(
          _TARGET_TYPEHASH,
          recipient.chainId,
          recipient.tokenId,
          recipient.wallet,
          recipient.amount
        )
      );
  }

  function _hash(Target memory recipient) private view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          _domainSeparator,
          _hashRecipient(recipient)
        )
      );
  }

  function _getChainID() private view returns (uint256) {
    uint256 id;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      id := chainid()
    }
    return id;
  }

  function setSigner(address signer) external requiresAuth {
    validationSigner = signer;
    emit SignerSet(signer);
  }

  function claim(
    Target calldata recipient,
    uint8 v,
    bytes32 r,
    bytes32 s // bytes calldata signature
  ) external {
    address signatureSigner = _hash(recipient).recover(v, r, s);
    require(signatureSigner == validationSigner, "Invalid Signature");
    require(recipient.chainId == _getChainID(), "Invalid chainId");
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    // 3. Call Callback Mint Function
    idReturn[0] = recipient.tokenId;
    quantityReturn[0] = recipient.amount;
    core.modularMintCallback(recipient.wallet, idReturn, quantityReturn, "");
  }
}

