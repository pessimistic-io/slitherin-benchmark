//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Counters.sol";
import "./AccessControl.sol";
import "./Ownable.sol";

import "./DeedHashedStates.sol";

contract DeedHashedV2 is ERC721, AccessControl, Ownable {

  using Counters for Counters.Counter;
  Counters.Counter private _tokenIdCounter;

  event TokenMinted(uint256 indexed tokenId, DeedHashedStates.TokenState indexed tokenState, string indexed tokenURI);
  event TokenStateUpdated(uint256 indexed tokenId, DeedHashedStates.TokenState indexed tokenState, string indexed tokenURI);
  event TokenURIUpdated(uint256 indexed tokenId, DeedHashedStates.TokenState indexed tokenState, string indexed tokenURI);
  event TokenMetadataLocked(uint256 indexed tokenId);
  event TokenMetadataUnlocked(uint256 indexed tokenId);
  event ContractURIUpdated(string indexed contractURI);

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); // can mint -> 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
  bytes32 public constant TRANSFERRER_ROLE = keccak256("TRANSFERRER_ROLE"); // can transfer tokens -> 0x9c0b3a9882e11a6bfb8283b46d1e79513afb8024ee864cd3a5b3a9050c42a7d7
  bytes32 public constant STATE_UPDATER_ROLE = keccak256("STATE_UPDATER_ROLE"); // can manage state of tokens -> 0x7f496d3b3a5b8d5d66b1301ac9407fb7ebb241c9fb60310446582db629b01709
  bytes32 public constant METADATA_LOCKER_ROLE = keccak256("METADATA_LOCKER_ROLE"); // can lock metadata -> 0x0af1a227e20c738dadfc76971d0d110fd4b320a2b47db610f169242cda7cbd7e
  bytes32 public constant TOKEN_URI_UPDATER_ROLE = keccak256("TOKEN_URI_UPDATER_ROLE"); // can update tokenURI -> 0xd610886bde7b9b3561f4ecdece11096467246c56f3a9958246e8d8b56500f923
  bytes32 public constant CONTRACT_URI_UPDATER_ROLE = keccak256("CONTRACT_URI_UPDATER_ROLE"); // can update contractURI -> 0xa9268e694ac7275a7b48347399b83305791087d40fd36a11330099e5e322b4cd

  struct Token {
    DeedHashedStates.TokenState state;
    uint256 tokenId;
    string tokenURI;
    bool isMetadataLocked;
  }

  mapping (uint256 => Token) internal tokens;

  string public contractURI;

  // Token name
  string private _name;

  // Token symbol
  string private _symbol;

  constructor(
    address _roleAdmin,
    string memory _tokenName,
    string memory _tokenSymbol,
    string memory _contractURI
  ) ERC721(_tokenName, _tokenSymbol) {
    _name = _tokenName;
    _symbol = _tokenSymbol;
    contractURI = _contractURI;
    _transferOwnership(_roleAdmin);
    _setupRole(DEFAULT_ADMIN_ROLE, _roleAdmin);
    _setupRole(MINTER_ROLE, _roleAdmin);
    _setupRole(TRANSFERRER_ROLE, _roleAdmin);
    _setupRole(STATE_UPDATER_ROLE, _roleAdmin);
    _setupRole(METADATA_LOCKER_ROLE, _roleAdmin);
    _setupRole(TOKEN_URI_UPDATER_ROLE, _roleAdmin);
    _setupRole(CONTRACT_URI_UPDATER_ROLE, _roleAdmin);
  }

  modifier onlyTransferrer() {
    require(hasRole(TRANSFERRER_ROLE, msg.sender), "CONTACT_PROPY_FOR_TRANSFER");
    _;
  }

  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, msg.sender), "NOT_MINTER");
    _;
  }

  modifier onlyStateUpdater() {
    require(hasRole(STATE_UPDATER_ROLE, msg.sender), "NOT_STATUS_UPDATER");
    _;
  }

  modifier onlyContractURIUpdater() {
    require(hasRole(CONTRACT_URI_UPDATER_ROLE, msg.sender), "NOT_CONTRACT_URI_UPDATER");
    _;
  }

  modifier onlyTokenURIUpdater() {
    require(hasRole(TOKEN_URI_UPDATER_ROLE, msg.sender), "NOT_TOKEN_URI_UPDATER");
    _;
  }

  modifier onlyStateAndTokenURIUpdater() {
    require(hasRole(STATE_UPDATER_ROLE, msg.sender), "NOT_STATUS_UPDATER");
    require(hasRole(TOKEN_URI_UPDATER_ROLE, msg.sender), "NOT_TOKEN_URI_UPDATER");
    _;
  }

  modifier onlyMetadataLocker() {
    require(hasRole(METADATA_LOCKER_ROLE, msg.sender), "NOT_METADATA_LOCKER");
    _;
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function mint(
    address _to,
    string memory _tokenURI
  ) public onlyMinter {
    require(bytes(_tokenURI).length > 0, "EMPTY_TOKEN_URI");
    _tokenIdCounter.increment();
    _mint(_to, _tokenIdCounter.current());
    tokens[_tokenIdCounter.current()] = Token(
      DeedHashedStates.TokenState.InitialSetup,
      _tokenIdCounter.current(),
      _tokenURI,
      false
    );
    emit TokenMinted(_tokenIdCounter.current(), DeedHashedStates.TokenState.InitialSetup, _tokenURI);
  }

  // UPDATE METADATA FUNCTIONS

  function updateTokenNameAndSymbol(
    string memory _tokenName,
    string memory _tokenSymbol
  ) public onlyOwner {
    _name = _tokenName;
    _symbol = _tokenSymbol;
  }

  function updateContractURI(
    string memory _contractURI
  ) public onlyContractURIUpdater {
    contractURI = _contractURI;
    emit ContractURIUpdated(_contractURI);
  }

  function updateTokenState(
    uint256 _tokenId,
    DeedHashedStates.TokenState _state
  ) public onlyStateUpdater {
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    Token storage token = tokens[_tokenId];
    require(token.isMetadataLocked == false, "METADATA_LOCKED");
    token.state = _state;
    emit TokenStateUpdated(_tokenId, _state, token.tokenURI);
  }

  function updateTokenURI(
    uint256 _tokenId,
    string memory _tokenURI
  ) public onlyTokenURIUpdater {
    require(bytes(_tokenURI).length > 0, "EMPTY_TOKEN_URI");
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    Token storage token = tokens[_tokenId];
    require(token.isMetadataLocked == false, "METADATA_LOCKED");
    token.tokenURI = _tokenURI;
    emit TokenURIUpdated(_tokenId, token.state, _tokenURI);
  }

  function updateTokenStateAndURI(
    uint256 _tokenId,
    DeedHashedStates.TokenState _state,
    string memory _tokenURI
  ) public onlyStateAndTokenURIUpdater {
    require(bytes(_tokenURI).length > 0, "EMPTY_TOKEN_URI");
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    Token storage token = tokens[_tokenId];
    require(token.isMetadataLocked == false, "METADATA_LOCKED");
    token.state = _state;
    token.tokenURI = _tokenURI;
    emit TokenStateUpdated(_tokenId, _state, _tokenURI);
    emit TokenURIUpdated(_tokenId, _state, _tokenURI);
  }

  // VIEWS

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function tokenInfo(
    uint256 _tokenId
  ) public view returns (Token memory) {
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    return tokens[_tokenId];
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    return tokens[_tokenId].tokenURI;
  }

  // OPTIONAL METADATA LOCKING / UNLOCKING

  function lockMetadata(
    uint256 _tokenId
  ) public onlyMetadataLocker {
    require(_exists(_tokenId), "INVALID_TOKEN_ID");
    Token storage token = tokens[_tokenId];
    require(token.isMetadataLocked == false, "ALREADY_LOCKED");
    token.isMetadataLocked = true;
    emit TokenMetadataLocked(_tokenId);
  }

  function unlockMetadata(
    uint256 _tokenId
  ) public {
    require(_ownerOf(_tokenId) == msg.sender, "NOT_TOKEN_OWNER");
    Token storage token = tokens[_tokenId];
    require(token.isMetadataLocked == true, "ALREADY_UNLOCKED");
    token.isMetadataLocked = false;
    emit TokenMetadataUnlocked(_tokenId);
  }

  // SOULBOUND(ESQUE) LOGIC (CAN BE OVERRIDDEN BY PROPY ADMIN)

  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyTransferrer {
    _transfer(from, to, tokenId);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyTransferrer {
    safeTransferFrom(from, to, tokenId, "");
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes memory data
  ) public override onlyTransferrer {
    _safeTransfer(from, to, tokenId, data);
  }

}
