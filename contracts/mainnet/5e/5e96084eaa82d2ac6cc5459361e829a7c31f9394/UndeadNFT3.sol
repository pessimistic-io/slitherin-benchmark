// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Minting.sol";

contract UndeadNFT3 is ERC721Upgradeable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  string public baseUri;
  mapping(uint256 => uint256) public packageIds;
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE");

  // IMX
  mapping(uint256 => bytes) public blueprints;
  bytes32 public constant IMX_BRIDGE_ROLE = keccak256("IMX_BRIDGE_ROLE");

  event EBaseUri(string uri);
  event EPackage(uint256 tokenId, uint256 pkgId);

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(ERC721Upgradeable, AccessControlUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(_interfaceId);
  }

  function __UndeadNFT3_init(string memory name, string memory symbol) external initializer {
    __ERC721_init(name, symbol);
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(EDITOR_ROLE, _msgSender());
    __AccessControl_init();
    __ReentrancyGuard_init();
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseUri;
  }

  function setBaseUri(string memory uri) external onlyRole(EDITOR_ROLE) {
    baseUri = uri;
    emit EBaseUri(uri);
  }

  /**
   * IMX Asset Minting
   * https://docs.x.immutable.com/docs/asset-minting/
   * https://github.com/immutable/imx-contracts/blob/main/contracts/Mintable.sol
   */
  function mintFor(
    address to,
    uint256 quantity,
    bytes calldata mintingBlob
  ) external onlyRole(IMX_BRIDGE_ROLE) {
    require(quantity == 1, "Mintable: invalid quantity");
    (uint256 id, bytes memory blueprint) = Minting.split(mintingBlob);
    _safeMint(to, id);
    blueprints[id] = blueprint;
  }

  function multipleMint(
    address to,
    uint256 fromId,
    uint256 toId,
    uint256 pkgId
  ) external nonReentrant onlyRole(MINTER_ROLE) {
    for (uint256 i = fromId; i <= toId; i++) {
      _mint(to, i);
      packageIds[i] = pkgId;
    }
  }

  function mint(
    uint256 tokenId,
    address to,
    uint256 pkgId
  ) external nonReentrant onlyRole(MINTER_ROLE) {
    _mint(to, tokenId);
    packageIds[tokenId] = pkgId;
  }

  function setPackage(uint256 tokenId, uint256 pkgId) external onlyRole(EDITOR_ROLE) {
    packageIds[tokenId] = pkgId;
    emit EPackage(tokenId, pkgId);
  }

  function bulkBurn(uint256 fromId, uint256 toId) external onlyRole(BURNER_ROLE) {
    for (uint256 id = fromId; id <= toId; id++) {
      _burn(id);
    }
  }
}

