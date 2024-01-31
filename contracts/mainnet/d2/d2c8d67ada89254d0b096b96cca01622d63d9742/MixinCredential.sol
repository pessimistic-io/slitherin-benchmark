// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./CountersUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./MixinTemplate.sol";
import "./MixinAdminToken.sol";
import "./MixinStructs.sol";

contract MixinCredential is
  ERC721Upgradeable,
  ERC721EnumerableUpgradeable,
  MixinTemplate,
  MixinAdminToken
{
  using AddressUpgradeable for address;
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using MixinStructs for MixinStructs.TrustChainCredentialData;

  CountersUpgradeable.Counter private _tokenIdCounter;

  address private _holder;
  address private _issuerCredentialContract;
  uint private _tokenId;

  mapping(uint256 => MixinStructs.TrustChainCredentialData)
    private _credentialDataByTokenId;

  // Events
  event NewTrustChainCredential(
    address indexed issuer,
    address indexed issuerCredentialContract,
    address indexed holder,
    address credentialContract,
    uint256 tokenId,
    MixinStructs.TrustChainCredentialType credentialType,
    uint64 issueTimestamp,
    uint256 templateId
  );

  function __MixinCredential_init(
    address __holder,
    address issuerCredentialContract,
    uint256 tokenId
  ) internal onlyInitializing {
    _holder = __holder;
    _issuerCredentialContract = issuerCredentialContract;
    _tokenId = tokenId;
    __MixinTemplate_init();
    _grantRole(DEFAULT_ADMIN_ROLE, owner());
    _grantRole(DEFAULT_ADMIN_ROLE, holder());
  }

  function holder() public view returns (address) {
    return _holder;
  }

  function credentialByTokenId(
    uint256 tokenId
  ) public view returns (MixinStructs.TrustChainCredential memory) {
    MixinStructs.TrustChainCredentialData
      memory credentialData = _credentialDataByTokenId[tokenId];
    return
      MixinStructs.TrustChainCredential(
        credentialData,
        ownerOf(tokenId),
        tokenId
      );
  }

  function credential()
    public
    view
    returns (MixinStructs.TrustChainCredential memory)
  {
    if (_issuerCredentialContract != address(0)) {
      // not root credential
      MixinCredential issuerTrustChain = MixinCredential(
        _issuerCredentialContract
      );
      return issuerTrustChain.credentialByTokenId(_tokenId);
    }
    // it's root credential
    return
      MixinStructs.TrustChainCredential(
        MixinStructs.TrustChainCredentialData(
          MixinStructs.TrustChainCredentialType.ROOT,
          payable(address(this)),
          address(0),
          address(0),
          address(0),
          0,
          0,
          1,
          "Genesis Credential",
          "TrustChain Inc., owner and operator of trustchain.xyz, is a Delaware registered corporation that verifies organization identities and bring trust to their Web2 and Web3 activities.",
          0,
          "TrustChain.xyz",
          ""
        ),
        owner(),
        _tokenId
      );
  }

  function _issue(
    address to,
    MixinStructs.TrustChainCredentialType credentialType,
    string memory title,
    string memory claim,
    string memory metadata,
    uint256 templateId,
    string memory holderName
  ) internal returns (uint256) {
    require(bytes(title).length > 0, "Title cannot be empty");
    require(bytes(claim).length > 0, "Claim cannot be empty");
    require(!to.isContract(), "It's not allowed to issue to a contract");
    require(
      credentialType != MixinStructs.TrustChainCredentialType.ROOT,
      "It's not allowed to issue a root contract"
    );
    require(proxyAdminAddress != address(0), "MISSING_PROXY_ADMIN");

    require(
      credentialType != MixinStructs.TrustChainCredentialType.ADMIN ||
        !hasRole(DEFAULT_ADMIN_ROLE, to),
      "Already have admin credential"
    );

    // get trustChain version
    address _trustChainTemplateImpl = _trustChainTemplateImpl(
      trustChainTemplateLatestVersion
    );
    require(
      _trustChainTemplateImpl != address(0),
      "MISSING_TRUST_CHAIN_TEMPLATE"
    );

    uint64 issueTimestamp = uint64(block.timestamp);
    address issuer = holder();
    address signer = msg.sender;
    address issuerCredentialContract = address(this);
    _tokenIdCounter.increment();
    uint256 tokenId = _tokenIdCounter.current();

    address payable newTrustChain = payable(address(0));

    // create contract only for common type
    if (credentialType == MixinStructs.TrustChainCredentialType.COMMON) {
      bytes memory data = abi.encodeWithSignature(
        "initialize(address,address,uint256)",
        to,
        address(this),
        tokenId
      );

      // deploy a proxy pointing to impl
      TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
        _trustChainTemplateImpl,
        proxyAdminAddress,
        data
      );
      newTrustChain = payable(address(proxy));

      upgradeTrustChain(newTrustChain, trustChainTemplateLatestVersion);
    }

    // grant admin when issue admin credential
    if (credentialType == MixinStructs.TrustChainCredentialType.ADMIN) {
      _saveAdminTokenId(to, tokenId);
      _grantRole(DEFAULT_ADMIN_ROLE, to);
    }

    // mint
    _safeMint(to, tokenId);

    // save credential metadata
    _credentialDataByTokenId[tokenId] = MixinStructs.TrustChainCredentialData(
      credentialType,
      newTrustChain,
      issuer,
      issuerCredentialContract,
      signer,
      issueTimestamp,
      0,
      1,
      title,
      claim,
      templateId,
      holderName,
      metadata
    );

    // trigger event
    emit NewTrustChainCredential(
      issuer,
      issuerCredentialContract,
      to,
      newTrustChain,
      tokenId,
      credentialType,
      issueTimestamp,
      templateId
    );

    return tokenId;
  }

  function adminCredentialByOwner(
    address owner
  ) external view returns (MixinStructs.TrustChainCredential memory) {
    require(tokenIdByAdmin(owner) > 0, "Cannot find admin credential");
    return credentialByTokenId(tokenIdByAdmin(owner));
  }

  function credentialOfOwnerByIndex(
    address owner,
    uint256 index
  ) public view returns (MixinStructs.TrustChainCredential memory) {
    return credentialByTokenId(tokenOfOwnerByIndex(owner, index));
  }

  function tokenURI(
    uint256 tokenId
  ) public view override(ERC721Upgradeable) returns (string memory) {
    return super.tokenURI(tokenId);
  }

  function _burn(uint256 tokenId) internal override(ERC721Upgradeable) {
    super._burn(tokenId);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
    require(
      from == address(0) || to == address(0),
      "It cannot be transferred. It can only be revoked/burn by the token owner."
    );
    super._beforeTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(
    bytes4 interfaceId
  )
    public
    view
    virtual
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable, MixinTemplate)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}

