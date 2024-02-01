// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./AddressUpgradeable.sol";
import "./TransparentUpgradeableProxy.sol";
import "./ProxyAdmin.sol";

import "./MixinStructs.sol";
import "./MixinCredential.sol";

contract TrustChain is MixinCredential {
  using AddressUpgradeable for address;
  using MixinStructs for MixinStructs.TrustChainCredentialType;
  using MixinStructs for MixinStructs.TrustChainCredentialData;
  using MixinStructs for MixinStructs.TrustChainCredential;
  using MixinStructs for MixinStructs.IssueArgument;

  function initialize(
    address holder,
    address issuerCredentialContract,
    uint256 tokenId
  ) public initializer {
    __ERC721_init("TrustChainCredential", "TCC");
    __ERC721Enumerable_init();
    __MixinCredential_init(holder, issuerCredentialContract, tokenId);
  }

  function issue(
    address to,
    MixinStructs.TrustChainCredentialType credentialType,
    string memory title,
    string memory claim,
    string memory metadata,
    uint256 templateId,
    string memory holderName
  ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
    return
      _issue(
        to,
        credentialType,
        title,
        claim,
        metadata,
        templateId,
        holderName
      );
  }

  function batchIssue(
    MixinStructs.IssueArgument[] memory args
  ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256[] memory) {
    require(args.length < 50, "Max issue 50 for each call");
    uint256[] memory tokenIds = new uint256[](args.length);
    for (uint i = 0; i < args.length; i += 1) {
      uint256 _tokenID = _issue(
        args[i].to,
        args[i].credentialType,
        args[i].title,
        args[i].claim,
        args[i].metadata,
        args[i].templateId,
        args[i].holderName
      );
      tokenIds[i] = _tokenID;
    }
    return tokenIds;
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(MixinCredential) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}

