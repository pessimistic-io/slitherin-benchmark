// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./ECDSA.sol";
import "./console.sol";

contract SignatureEIP712 {
  using ECDSA for bytes32;

  struct EIP712Domain {
    string name;
    string version;
    uint256 chainId;
    address verifyingContract;
  }

  struct DealSignedStructure {
    uint256 dealId;
    uint256 payoutNonce;
    uint96 amount;
    address tokenAddress;
    address recipient;
    uint256 networkId;
    address safeAddress;
    address approver;
  }

  struct CancelNonce {
    uint256 nonce;
    address safeAddress;
  }

  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256(
      bytes(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
      )
    );

  bytes32 internal constant CANCEL_NONCE_TYPEHASH =
    keccak256(bytes("CancelNonce(uint256 nonce,address safeAddress)"));

  bytes32 internal constant DEAL_SIGNATURE_TYPEHASH =
    keccak256(
      bytes(
        "DealSignedStructure(uint256 dealId,uint256 payoutNonce,uint96 amount,address tokenAddress,address recipient,uint256 networkId,address safeAddress,address approver)"
      )
    );

  function getChainId() internal view returns (uint256 chainId) {
    assembly {
      chainId := chainid()
    }
  }

  struct DealSignedBulkStructure {
    uint256[] dealIds;
    uint256[] payoutNonces;
    uint96[] amounts;
    address[] tokenAddresses;
    address[] recipients;
    uint256[] networkIds;
    address[] safeAddresses;
    address approver;
  }

  bytes32 internal constant DEAL_SIGNATURE_BULK_TYPEHASH =
    keccak256(
      bytes(
        "DealSignedBulkStructure(uint256[] dealIds,uint256[] payoutNonces,uint96[] amounts,address[] tokenAddresses,address[] recipients,uint256[] networkIds,address[] safeAddresses,address approver)"
      )
    );

  bytes32 internal DOMAIN_SEPARATOR =
    keccak256(
      abi.encode(
        EIP712_DOMAIN_TYPEHASH,
        keccak256(bytes("DealManager")),
        keccak256(bytes("1.0")),
        getChainId(),
        // 1,
        address(this)
      )
    );

  function validateSingleDealSignature(
    address approver,
    uint256 _dealId,
    uint256 _payoutNonce,
    uint96 _amount,
    address _tokenAddress,
    address _recipient,
    uint256 _networkId,
    address _safeAddress,
    bytes memory signature
  ) public view returns (address) {
    DealSignedStructure memory dealTx = DealSignedStructure({
      dealId: _dealId,
      payoutNonce: _payoutNonce,
      amount: _amount,
      tokenAddress: _tokenAddress,
      recipient: _recipient,
      networkId: _networkId,
      safeAddress: _safeAddress,
      approver: approver
    });

    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            DEAL_SIGNATURE_TYPEHASH,
            dealTx.dealId,
            dealTx.payoutNonce,
            dealTx.amount,
            dealTx.tokenAddress,
            dealTx.recipient,
            dealTx.networkId,
            dealTx.safeAddress,
            dealTx.approver
          )
        )
      )
    );

    require(approver != address(0), "CS004");
    address signer = digest.recover(signature);
    return signer;
  }

  function validateBulkDealSignature(
    address _approver,
    uint256[] memory _dealIds,
    uint256[] memory _payoutNonces,
    uint96[] memory _amounts,
    address[] memory _tokenAddresses,
    address[] memory _recipients,
    uint256[] memory _networkIds,
    address[] memory _safeAddresses,
    bytes memory signature
  ) public view returns (address) {
    DealSignedBulkStructure memory dealTx = DealSignedBulkStructure({
      dealIds: _dealIds,
      payoutNonces: _payoutNonces,
      amounts: _amounts,
      tokenAddresses: _tokenAddresses,
      recipients: _recipients,
      networkIds: _networkIds,
      safeAddresses: _safeAddresses,
      approver: _approver
    });

    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            DEAL_SIGNATURE_BULK_TYPEHASH,
            keccak256(abi.encodePacked(dealTx.dealIds)),
            keccak256(abi.encodePacked(dealTx.payoutNonces)),
            keccak256(abi.encodePacked(dealTx.amounts)),
            keccak256(abi.encodePacked(dealTx.tokenAddresses)),
            keccak256(abi.encodePacked(dealTx.recipients)),
            keccak256(abi.encodePacked(dealTx.networkIds)),
            keccak256(abi.encodePacked(dealTx.safeAddresses)),
            dealTx.approver
          )
        )
      )
    );

    require(_approver != address(0), "CS004");
    address signer = digest.recover(signature);
    return signer;
  }

  function validateCancelNonceSignature(
    uint256 nonce,
    address safeAddress,
    bytes memory signature
  ) internal view returns (address) {
    CancelNonce memory cnTx = CancelNonce({
      nonce: nonce,
      safeAddress: safeAddress
    });

    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(CANCEL_NONCE_TYPEHASH, cnTx.nonce, cnTx.safeAddress)
        )
      )
    );

    address signer = digest.recover(signature);
    return signer;
  }
}

