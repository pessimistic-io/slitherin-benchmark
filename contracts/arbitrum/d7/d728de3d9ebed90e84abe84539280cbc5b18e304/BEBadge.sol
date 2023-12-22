// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./ERC721Enumerable.sol";
import "./AccessControl.sol";
import "./IMetaData.sol";

contract BEBadge is AccessControl, ERC721Enumerable {
  mapping(uint256 => bool) public lockedTokens;
  address private _metaAddress;
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
  bytes32 public constant LOCK_ROLE = keccak256("LOCK_ROLE");
  uint256 public immutable supplyLimit;
  uint256 tokenIndex;
  uint256 public maxBatchSize = 500;

  event Lock(uint256 indexed tokenId);
  event UnLock(uint256 indexed tokenId);

  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _supplyLimt
  ) ERC721(_name, _symbol) {
    _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(BURN_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(LOCK_ROLE, DEFAULT_ADMIN_ROLE);

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setupRole(BURN_ROLE, msg.sender);
    _setupRole(LOCK_ROLE, msg.sender);
    supplyLimit = _supplyLimt;
  }

  /**
   * @dev Batch mint tokens and transfer to specified address.
   *
   * Requirements:
   * - Caller must have `MINTER_ROLE`.
   * - The total supply limit should not be exceeded.
   * - The number of tokenIds offered for minting should not exceed 100.
   */

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
      tokenIndex += 1;
      uint256 tokenId = tokenIndex;
      _safeMint(to, tokenId);
      tokenIds[i] = tokenId;
    }
    return tokenIds;
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
   * @dev grant burn role to address
   */
  function setBurnRole(address to) external {
    grantRole(BURN_ROLE, to);
  }

  /**
   * @dev Remove burn role to address
   */
  function removeBurnRole(address proxy) external {
    revokeRole(BURN_ROLE, proxy);
  }

  /**
   * @dev Add address for lock item
   */
  function grantLockRole(address to) external {
    grantRole(LOCK_ROLE, to);
  }

  /**
   * @dev Remove address for lock item
   */
  function removeLockRole(address account) external {
    revokeRole(LOCK_ROLE, account);
  }

  /**
   * @dev Lock token to use in game or for rental
   */
  function lock(uint256 tokenId) external onlyRole(LOCK_ROLE) {
    require(_exists(tokenId), "Must be valid tokenId");
    require(!lockedTokens[tokenId], "Token has already locked");
    lockedTokens[tokenId] = true;
    emit Lock(tokenId);
  }

  /**
   * @dev Unlock token to use blockchain or sale on marketplace
   */
  function unlock(uint256 tokenId) external onlyRole(LOCK_ROLE) {
    require(_exists(tokenId), "Must be valid tokenId");
    require(lockedTokens[tokenId], "Token has already unlocked");
    lockedTokens[tokenId] = false;
    emit UnLock(tokenId);
  }

  /**
   * @dev Set token URI
   */
  function updateMetaAddress(
    address metaAddress
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _metaAddress = metaAddress;
  }

  function updateBatchLimit(
    uint256 valNew
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(valNew > 0, "batch size too short");
    maxBatchSize = valNew;
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

  /**
   * @dev See {IERC165-_beforeTokenTransfer}.
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 firstTokenId,
    uint256 batchSize
  ) internal virtual override {
    super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
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

  /**
   * @dev Burns `tokenId`.
   *
   * Requirements:
   *
   * - The caller must own `tokenId` or be an approved operator.
   */
  function burn(
    address owner,
    uint256 tokenId
  ) external virtual onlyRole(BURN_ROLE) {
    require(_exists(tokenId), "TokenId not exists");
    require(!lockedTokens[tokenId], "Can not burn locked token");
    require(
      ownerOf(tokenId) == owner,
      "current address is not owner of this item now"
    );
    _burn(tokenId);
  }
}

