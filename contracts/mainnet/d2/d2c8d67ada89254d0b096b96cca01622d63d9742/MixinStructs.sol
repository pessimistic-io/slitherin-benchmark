// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library MixinStructs {
  enum TrustChainCredentialType {
    COMMON,
    ADMIN,
    VIEW_ONLY,
    ROOT
  }

  struct TrustChainCredentialData {
    TrustChainCredentialType credentialType;
    address payable credentialContract;
    address issuer;
    address issuerCredentialContract;
    address signer;
    uint64 issueTimestamp;
    uint64 expirationTimestamp;
    uint8 status; // 0: disabled 1: enabled, others: placeholder
    string title;
    string claim;
    uint256 templateId;
    string holderName;
    string metadata;
  }

  struct TrustChainCredential {
    TrustChainCredentialData data;
    address holder;
    uint256 tokenId;
  }

  struct IssueArgument {
    address to;
    MixinStructs.TrustChainCredentialType credentialType;
    string title;
    string claim;
    string metadata;
    uint256 templateId;
    string holderName;
  }
}

