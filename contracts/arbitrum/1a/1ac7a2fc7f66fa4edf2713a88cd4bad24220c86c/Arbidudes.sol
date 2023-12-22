// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";

/* 

      _____________________________________
     |                                     |
     |                  The                |
     |               ARBIDUDES             |
     |             Dudes Gen One           |
     |      https://www.arbidudes.xyz/     |
     |          Twitter: @ArbiDudes        |
     |_____________________________________|


//////////////////////////////////////////////////
/////////////@@@@@@@@@@@//////////////////////////
/////////@@@@@@@@@@@@@@@@@////////////////////////
///////@@@@@@@@@@@@@@@@@@@@@//////////////////////
/////@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@///////
/////@@......@@@@@@/...................//////@@///
/////@@..........@@/...................//////@@///
/////@@....@@@@...............@@@@.....//////@@///
/////&&....@@@@...............@@@@.....//////&&///
/////@@....@@@@...............@@@@.....//////@@///
/////@@..****...................*****..//////@@///
/////@@....@@@@@@@@@@@@@@@@@@@@@.......//////@@///
/////@&................................//////@&///
/////@@......@@@@@@/...................//////@@///
/////@@..............................////////@@///
/////@@..............................////////@@///
/////&&...........................///////////&&///
///////@&//.....................///////////@@/////
/////////@@////////,......///////////////@@///////
///////////@@@@......./////////////////@&@@///////

*/

contract ArbiDudesGenOne is
  ERC721,
  ERC721Enumerable,
  Pausable,
  Ownable,
  ReentrancyGuard
{
  using Counters for Counters.Counter;

  uint256 public price = 50000000000000000; //0.05 ETH
  uint256 public changeNamePrice = 10000000000000000; // 0.01 ETH
  uint256 public chatPrice = 0;
  uint256 public maxGiveawayTokenId = 550;
  uint256 private _maxSupply = 10000;
  uint256 private _maxMintAmount = 20;

  Counters.Counter private _tokenIdCounter;

  event ArbiDudeCreated(uint256 indexed tokenId, uint256 indexed soul);
  event NameChanged(uint256 tokenId, string name);

  struct Dude {
    string nickname;
    mapping(uint256 => EternalMessage[]) chats; // tokenId -> chat
    mapping(uint256 => uint256) blockedChat; // tokenId -> blocked
  }

  struct EternalMessage {
    string message;
    uint256 from;
    uint256 timestamp;
  }

  mapping(uint256 => Dude) private dudes;
  mapping(uint256 => uint256) private souls;
  mapping(address => bool) public mintedFree;

  constructor(string memory newBaseURI, uint256 newMaxSupply)
    ERC721("ArbiDudesGenOne", "DUDE")
  {
    setBaseURI(newBaseURI);
    setMaxSupply(newMaxSupply);

    // Increment tokenIdCounter so it starts at one
    _tokenIdCounter.increment();
  }

  function getCurrentTokenId() public view returns (uint256) {
    return _tokenIdCounter.current();
  }

  function getDudeName(uint256 _tokenId) public view returns (string memory) {
    // Dude info is public - chats are private
    return dudes[_tokenId].nickname;
  }

  function getDudesChat(uint256 _tokenId, uint256 _to)
    public
    view
    returns (EternalMessage[] memory)
  {
    require(
      _isApprovedOrOwner(msg.sender, _tokenId),
      "ERC721: Not owner nor approved"
    );
    require(souls[_to] == _tokenId, "These ArbiDudes aren't soulmates");
    require(
      dudes[_tokenId].blockedChat[_to] == 0 &&
        dudes[_to].blockedChat[_tokenId] == 0,
      "Chat is blocked"
    );

    return dudes[_tokenId].chats[_to];
  }

  function setPublicPrice(uint256 newPrice) public onlyOwner {
    price = newPrice;
  }

  function setChangeNamePrice(uint256 newPrice) public onlyOwner {
    changeNamePrice = newPrice;
  }

  function setChatPrice(uint256 newPrice) public onlyOwner {
    chatPrice = newPrice;
  }

  function setMaxGiveawayTokenId(uint256 _newMaxToken) public onlyOwner {
    maxGiveawayTokenId = _newMaxToken;
  }

  function setMaxSupply(uint256 _newMaxSupply) private {
    _maxSupply = _newMaxSupply;
  }

  function ownerWithdraw() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  /**
   * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
   * in child contracts.
   */
  string private baseURI = "";

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }

  function setBaseURI(string memory newBaseURI) public onlyOwner {
    baseURI = newBaseURI;
  }

  // Souls
  function soulAssignment(uint256 tokenId) internal {
    if (souls[tokenId] == 0) {
      uint256 next = tokenId + 25;
      if (next > _maxSupply) {
        uint256 n = tokenId + 25 - _maxSupply;
        next = n + tokenId;
      }
      souls[tokenId] = next;
      souls[next] = tokenId;
    }
  }

  function getSoul(uint256 tokenId) public view returns (uint256) {
    return souls[tokenId];
  }

  // Mint
  modifier tokenMintable(uint256 tokenId) {
    require(tokenId > 0 && tokenId <= _maxSupply, "Token ID invalid");
    require(price <= msg.value, "Ether value sent is not correct");
    _;
  }

  // Only called internally
  function _internalMint(address to) internal {
    // minting logic
    uint256 tokenId = _tokenIdCounter.current();
    require(tokenId > 0 && tokenId <= _maxSupply, "Token ID invalid");
    _safeMint(to, tokenId);
    soulAssignment(tokenId);
    emit ArbiDudeCreated(tokenId, souls[tokenId]);
    _tokenIdCounter.increment();
  }

  // Normal mint
  function mint()
    public
    payable
    nonReentrant
    tokenMintable(_tokenIdCounter.current())
  {
    _internalMint(_msgSender());
  }

  function mintFree() public nonReentrant {
    require(mintedFree[msg.sender] != true, "Already minted for free");
    uint256 tokenId = _tokenIdCounter.current();
    require(tokenId <= maxGiveawayTokenId, "No more free Dudes at the moment");
    _internalMint(_msgSender());
    mintedFree[msg.sender] = true;
  }

  // Mint multiple units
  function mintMultiple(uint256 _num) public payable {
    address to = _msgSender();
    require(_num > 0, "The minimum is one dude");
    require(_num <= _maxMintAmount, "You can mint a max of 20 dudes");
    require(msg.value >= price * _num, "Ether sent is not enough");

    for (uint256 i; i < _num; i++) {
      _internalMint(to);
    }
  }

  // Allow the owner to claim any amount of NFTs and direct them to another address.
  function ownerClaimMultiple(uint256 amount, address to)
    public
    nonReentrant
    onlyOwner
  {
    require(amount > 0, "The minimum is one dude");
    for (uint256 i = 0; i < amount; i++) {
      _internalMint(to);
    }
  }

  // Name
  function changeName(uint256 _tokenId, string memory _name)
    external
    payable
    nonReentrant
  {
    require(msg.value >= changeNamePrice, "Eth sent is not enough");
    require(
      _isApprovedOrOwner(msg.sender, _tokenId),
      "ERC721: Not owner nor approved"
    );
    require(
      bytes(_name).length <= 20 && bytes(_name).length > 2,
      "Name between 3 and 20 characters"
    );
    dudes[_tokenId].nickname = _name;
    emit NameChanged(_tokenId, _name);
  }

  // Chat
  modifier canSendMessage(
    uint256 _from,
    uint256 _to,
    string memory _text
  ) {
    require(
      _isApprovedOrOwner(msg.sender, _from),
      "ERC721: Not owner nor approved"
    );
    require(souls[_from] == _to, "These Arbidudes aren't soulmates");
    require(
      bytes(_text).length <= 140 && bytes(_text).length > 2,
      "Text between 3 and 140 long"
    );
    _;
  }

  function sendMessage(
    uint256 _from,
    uint256 _to,
    string memory _text
  ) external payable nonReentrant canSendMessage(_from, _to, _text) {
    require(
      dudes[_from].blockedChat[_to] == 0 && dudes[_to].blockedChat[_from] == 0,
      "Chat is blocked"
    );
    Dude storage fromDude = dudes[_from];
    Dude storage toDude = dudes[_to];

    // Eternal message - stored in the blockchain
    if (
      fromDude.chats[_to].length == 0 || fromDude.chats[_to].length % 5 == 0
    ) {
      require(chatPrice <= msg.value, "Eth not enough to unlock chat");
    }
    EternalMessage memory eternalMessage = EternalMessage(
      _text,
      _from,
      block.timestamp
    );
    fromDude.chats[_to].push(eternalMessage);
    toDude.chats[_from].push(eternalMessage);
  }

  function deleteChat(uint256 _from, uint256 _to)
    external
    nonReentrant
    canSendMessage(_from, _to, "DELETE")
  {
    delete dudes[_from].chats[_to];
    delete dudes[_to].chats[_from];
  }

  function blockChat(
    uint256 _from,
    uint256 _to,
    uint256 _block
  ) external nonReentrant canSendMessage(_from, _to, "BLOCK") {
    dudes[_from].blockedChat[_to] = _block;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}

