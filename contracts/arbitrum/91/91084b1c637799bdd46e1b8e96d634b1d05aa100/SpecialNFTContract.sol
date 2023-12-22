// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./SafeMathUpgradeable.sol";


contract SpecialNFTContract is
  ERC721EnumerableUpgradeable,
  OwnableUpgradeable
{
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using StringsUpgradeable for uint256;

  mapping(address => bool) private adminAccess;
  mapping(uint256 => uint256) private specialNFTTypes;

  CountersUpgradeable.Counter private _tokenIdCounter;
  event SetAdminAccess(address indexed user, bool access);

  function initialize() public initializer {
    __ERC721Enumerable_init();
    __ERC721_init("Battlefly Special NFTs", "BattleflySNFT");
    __Ownable_init();
  }

  function setAdminAccess(address user, bool access) external onlyOwner {
    adminAccess[user] = access;
    emit SetAdminAccess(user, access);
  }
  function mintSpecialNFTs(address receiver, uint256 _specialNFTType, uint256 amount) external
    onlyAdminAccess
    returns (uint256[] memory) {
      uint256[] memory tokenIds = new uint256[](amount);
      for(uint256 i = 0; i < amount; i++) {
        uint256 nextTokenId = _getNextTokenId();
        _mint(receiver, nextTokenId);
        specialNFTTypes[nextTokenId] = _specialNFTType;
        tokenIds[i] = nextTokenId;
      }
      return tokenIds;
  }
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
      require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
      return string(abi.encodePacked("https://api.battlefly.game/specials/", tokenId.toString(), "/metadata"));
  }
  function mintSpecialNFT(address receiver, uint256 specialNFTType)
    external
    onlyAdminAccess
    returns (uint256)
  {
    uint256 nextTokenId = _getNextTokenId();
    _mint(receiver, nextTokenId);
    specialNFTTypes[nextTokenId] = specialNFTType;
    return nextTokenId;
  }
  function getSpecialNFTType(uint256 tokenId) external view returns (uint256) {
    return specialNFTTypes[tokenId];
  }
  function _getNextTokenId() private view returns (uint256) {
    return (_tokenIdCounter.current() + 1);
  }
  function _mint(address to, uint256 tokenId)
    internal
    override(ERC721Upgradeable)
  {
    super._mint(to, tokenId);
    _tokenIdCounter.increment();
  }

  modifier onlyAdminAccess() {
    require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
    _;
  }
}

