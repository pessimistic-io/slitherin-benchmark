// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./StringsUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";

import "./IERC20Upgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IAviveNFTBase.sol";

abstract contract AviveNFTBase is
  Initializable,
  ERC721Upgradeable,
  ERC721BurnableUpgradeable,
  UUPSUpgradeable,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  IAviveNFTBase
{
  using StringsUpgradeable for uint256;

  uint256 public totalSupply;
  bool public TradingOpen;
  string private _baseuri;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  // external functions
  function setTradingOpen(bool open) external onlyOwner {
    TradingOpen = open;
  }

  function setBaseURI(string memory uri) external onlyOwner {
    require(bytes(uri).length > 0, "wrong base uri");
    _baseuri = uri;
  }

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    _requireMinted(tokenId);
    return string(abi.encodePacked(_baseuri, tokenId.toString(), "/"));
  }

  function withdraw(uint256 amount) external virtual onlyOwner {
    uint256 balance = address(this).balance;
    require(balance >= amount, "not enough balance");
    payable(msg.sender).transfer(amount);
  }

  function withdrawToken(
    address token,
    uint256 amount
  ) external virtual nonReentrant onlyOwner {
    uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
    require(balance >= amount, "not enough balance");
    IERC20Upgradeable(token).transfer(msg.sender, amount);
  }

  // internal functions

  function __AviveNFTBase__init(
    string calldata baseuri_,
    string memory name_,
    string memory symbol_
  ) internal initializer {
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    OwnableUpgradeable.__Ownable_init();
    UUPSUpgradeable.__UUPSUpgradeable_init();
    ERC721BurnableUpgradeable.__ERC721Burnable_init();
    ERC721Upgradeable.__ERC721_init(name_, symbol_);
    _baseuri = baseuri_;
    TradingOpen = false;
    totalSupply = 0;
  }

  // The following functions are overrides required by Solidity.
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal virtual override(ERC721Upgradeable) {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
    if (from == address(0)) {
      totalSupply += batchSize;
    } else if (to != address(0)) {
      require(TradingOpen, "trading not open");
    }
    if (to == address(0)) {
      totalSupply -= batchSize;
    }
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(ERC721Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  receive() external payable {}

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[47] private __gap;
}

