// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./ERC721Enumerable.sol";
import "./AccessControl.sol";

contract NFT is AccessControl, ERC721Enumerable {
  mapping(uint256 => bool) public lockedTokens;
  string private _baseTokenURI = "https://market.cebg.games/api/nft/info/";
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant LOCK_ROLE = keccak256("LOCK_ROLE");
  uint256 public immutable supplyLimit;

  event Lock(uint256 indexed tokenId);
  event UnLock(uint256 indexed tokenId);
  event BatchMint(address indexed to, uint256[] tokenIds);

  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _supplyLimt
  ) ERC721(_name, _symbol) {
    _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(LOCK_ROLE, DEFAULT_ADMIN_ROLE);

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setupRole(LOCK_ROLE, msg.sender);
    supplyLimit = _supplyLimt;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
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
    uint256[] memory tokenIds
  ) external onlyRole(MINTER_ROLE) {
    uint256 count = tokenIds.length;
    require(count <= 100, "tokenIds too many");
    if (supplyLimit > 0) {
      require(
        (totalSupply() + count) <= supplyLimit,
        "Exceed the total supply"
      );
    }
    for (uint256 i = 0; i < count; i++) {
      uint256 tokenId = tokenIds[i];
      _safeMint(to, tokenId);
    }
    emit BatchMint(to, tokenIds);
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
   * @dev Add address for lock item
   */
  function setLockRole(address to) external {
    grantRole(LOCK_ROLE, to);
  }

  /**
   * @dev Remove address for lock item
   */
  function removeLockRole(address to) external {
    revokeRole(LOCK_ROLE, to);
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
  function updateBaseURI(
    string calldata baseTokenURI
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _baseTokenURI = baseTokenURI;
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

  function burn(uint256 tokenId) external virtual {
    require(
      _isApprovedOrOwner(_msgSender(), tokenId),
      "caller is not owner nor approved"
    );
    _burn(tokenId);
  }
}

