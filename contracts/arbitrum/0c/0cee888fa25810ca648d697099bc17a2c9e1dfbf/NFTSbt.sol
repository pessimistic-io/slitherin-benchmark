// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./AccessControl.sol";
import "./IMetaData.sol";

contract NFTSbt is AccessControl, ERC721Enumerable {
  using Counters for Counters.Counter;
  address private _metaAddress;
  bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  uint256 public immutable supplyLimit;

  Counters.Counter private _tokenIdCounter;

  uint256 public maxBatchSize = 500;

  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _supplyLimt
  ) ERC721(_name, _symbol) {
    supplyLimit = _supplyLimt;
    _setRoleAdmin(BURN_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setupRole(BURN_ROLE, msg.sender);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(
    bytes4 interfaceId
  )
    public
    view
    virtual
    override(AccessControl, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 firstTokenId,
    uint256 batchSize
  ) internal virtual override {
    require(from == address(0) || to == address(0), "Token not transferable");
    super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
  }

  /**
   * @dev Set token URI
   */
  function updateMetaAddress(
    address metaAddress
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _metaAddress = metaAddress;
  }

  /**
   * @dev one type badge has same tokenURI
   */
  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    require(_exists(tokenId), "URI query for nonexistent token");
    return IMetaData(_metaAddress).getMetaData(address(this), tokenId);
  }

  function batchMint(
    address to,
    uint256 count
  ) external onlyRole(MINTER_ROLE) returns (uint256[] memory) {
    require(count > 0, "tokenIds too small");
    require(count <= maxBatchSize, "tokenIds too many");
    if (supplyLimit > 0) {
      require(
        (totalSupply() + count) <= supplyLimit,
        "Exceed the total supply"
      );
    }
    uint256[] memory tokenIds = new uint256[](count);
    for (uint256 i = 0; i < count; i++) {
      _tokenIdCounter.increment();
      uint256 tokenId = _tokenIdCounter.current();
      _safeMint(to, tokenId);
      tokenIds[i] = tokenId;
    }
    return tokenIds;
  }

  function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
    require(to != address(0), "Cannot mint to zero address");
    if (supplyLimit > 0) {
      require((totalSupply() + 1) <= supplyLimit, "Exceed the total supply");
    }
    _tokenIdCounter.increment();
    uint256 tokenId = _tokenIdCounter.current();
    _safeMint(to, tokenId);
    return tokenId;
  }

  function burn(uint256 tokenId) external onlyRole(BURN_ROLE) {
    require(
      _isApprovedOrOwner(_msgSender(), tokenId),
      "Caller is not owner nor approved"
    );
    _burn(tokenId);
  }

  /**
   * @dev Grant mint role to address
   */
  function setMintRole(address to) external {
    grantRole(MINTER_ROLE, to);
  }

  /**
   * @dev Remove mint role to address
   */
  function removeMintRole(address to) external {
    revokeRole(MINTER_ROLE, to);
  }

  /**
   * @dev Grant burn role to address
   */
  function setBurnRole(address to) external {
    grantRole(BURN_ROLE, to);
  }

  /**
   * @dev Remove burn role to address
   */
  function removeBurnRole(address to) external {
    revokeRole(BURN_ROLE, to);
  }
}

