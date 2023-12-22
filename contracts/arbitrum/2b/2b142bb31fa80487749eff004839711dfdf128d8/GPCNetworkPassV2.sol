// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC721Upgradeable.sol";
import "./God.sol";
import "./Initializable.sol";

contract GPCNetworkPassV2 is ERC721Upgradeable, God {
  uint256 private _tokenId;

  uint256 public totalMembers;

  mapping(address => bool) private admins;

  mapping(uint256 => string) private _tokenURI;

  mapping(uint256 => uint256) public memberSince;

  mapping(address => uint256) public memberNumber;

  mapping(uint256 => string[]) private _memberDistinctions;

  mapping(uint256 => bool) public inactiveMembers;

  event AdminAdded(address indexed admin);
  event AdminRemoved(address indexed admin);
  event WelcomeMember(uint256 indexed tokenId, address indexed newMember, string uri);
  event MembershipRevoked(uint256 indexed tokenId, address indexed revokedMember);
  event DistinctionAdded(uint256 indexed tokenId, string distinction, string uri);
  event DistinctionRemoved(uint256 indexed tokenId, string distinction, string uri);
  event StatusChanged(uint256 indexed tokenId, bool inactive, string uri);

  constructor() {}

  function initialize(string memory name_, string memory symbol_, address god_) external initializer {
    ERC721Upgradeable.__ERC721_init(name_, symbol_);
    God.__God_init(god_);
  }

  modifier onlyAdmin() {
    require(msg.sender == god() || admins[msg.sender], 'not admin');
    _;
  }

  function addAdmin(address admin) external onlyGod {
    admins[admin] = true;
    emit AdminAdded(admin);
  }

  function removeAdmin(address admin) external onlyGod {
    delete admins[admin];
    emit AdminRemoved(admin);
  }

  function mintMembers(address[] memory members, string[] memory uri) external onlyAdmin {
    require(members.length == uri.length);
    for (uint8 i; i < members.length; i++) {
      mintMember(members[i], uri[i]);
    }
  }

  function mintMember(address member, string memory uri) public onlyAdmin {
    require(balanceOf(member) == 0, 'already a member');
    _tokenId++;
    totalMembers++;
    _safeMint(member, _tokenId);
    _updateTokenURI(_tokenId, uri);
    memberSince[_tokenId] = block.timestamp;
    memberNumber[member] = _tokenId;
    emit WelcomeMember(_tokenId, member, uri);
  }

  function revokeMembership(uint256 tokenId) external onlyAdmin {
    _requireMinted(tokenId);
    address member = ownerOf(tokenId);
    _burn(tokenId);
    totalMembers -= 1;
    delete _tokenURI[tokenId];
    delete memberNumber[member];
    delete memberSince[tokenId];
    delete _memberDistinctions[tokenId];
    emit MembershipRevoked(tokenId, member);
  }

  function addDistinction(uint256 tokenId, string memory distinction, string memory uri) public onlyAdmin {
    _requireMinted(tokenId);
    _memberDistinctions[tokenId].push(distinction);

    _updateTokenURI(tokenId, uri);
    emit DistinctionAdded(tokenId, distinction, uri);
  }

  function bulkAddDistinctions(
    uint256[] memory tokenIds,
    string[] memory distinctions,
    string[] memory uri
  ) external onlyAdmin {
    require(tokenIds.length == distinctions.length && tokenIds.length == uri.length);
    for (uint256 i; i < tokenIds.length; i++) {
      addDistinction(tokenIds[i], distinctions[i], uri[i]);
    }
  }

  function removeDistinction(uint256 tokenId, uint256 distinctionIndex, string memory uri) external onlyAdmin {
    _requireMinted(tokenId);

    uint256 distinctionCount = _memberDistinctions[tokenId].length;
    require(distinctionIndex >= 0 && distinctionIndex < distinctionCount, 'invalid distinction');

    string memory distinction = _memberDistinctions[tokenId][distinctionIndex];

    if (distinctionIndex != distinctionCount)
      _memberDistinctions[tokenId][distinctionIndex] = _memberDistinctions[tokenId][distinctionCount - 1];
    _memberDistinctions[tokenId].pop();

    _updateTokenURI(tokenId, uri);
    emit DistinctionRemoved(tokenId, distinction, uri);
  }

  function updateActiveStatus(uint256 tokenId, bool inactive, string memory uri) external onlyAdmin {
    inactiveMembers[tokenId] = inactive;
    emit StatusChanged(tokenId, inactive, uri);
  }

  function updateTokenURI(uint256 tokenId, string memory uri) external onlyAdmin {
    _updateTokenURI(tokenId, uri);
  }

  function bulkUpdateURIs(uint256[] memory tokenIds, string[] memory uri) external onlyAdmin {
    require(tokenIds.length == uri.length);
    for (uint8 i; i < tokenIds.length; i++) {
      _updateTokenURI(tokenIds[i], uri[i]);
    }
  }

  function memberDistinctions(uint256 tokenId) public view returns (string[] memory) {
    _requireMinted(tokenId);
    return _memberDistinctions[tokenId];
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    _requireMinted(tokenId);
    return _tokenURI[tokenId];
  }

  function owner() public view returns (address) {
    return god();
  }

  function _updateTokenURI(uint256 tokenId, string memory uri) internal {
    _tokenURI[tokenId] = uri;
  }

  function _transfer(address from, address to, uint256 tokenId) internal virtual override {
    revert('Not transferrable');
  }

  function currentTokenId() public view returns (uint256 tokenId) {
    return _tokenId;
  }
}

