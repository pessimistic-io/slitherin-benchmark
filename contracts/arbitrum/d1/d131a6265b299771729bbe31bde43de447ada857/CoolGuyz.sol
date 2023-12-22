// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./MerkleProof.sol";


/* 

      _____________________________________
     |                                     |
     |                  The                |
     |               CoolGuyz              |
     |      https://www.guyz.cool/         |
     |        Twitter: @CoolGuyzMafia      |
     |_____________________________________|
     

*/

contract CoolGuyz is
  ERC721,
  ERC721Enumerable,
  Pausable,
  Ownable,
  ReentrancyGuard
{
  using Counters for Counters.Counter;

  uint256 public price = 75000000000000000; //0.075 ETH
  uint256 private _maxSupply = 10000;
  uint256 private _maxMintAmount = 20;
  bool public whiteListActive = false;
  bytes32 public merkleRoot;
  mapping(address => uint256) public whiteListClaimed;


  Counters.Counter private _tokenIdCounter;

  struct guy {
    uint256 speed;
    uint256 intelligence;
    uint256 strength;
    uint256 wisdom;
    uint256 defense;
    uint256 agility;
    uint256 charisma;
    uint256 weight;
    uint256 height;
  }

  event CoolGuyCreated(uint256 tokenId, guy guyCreated);

  mapping(uint256 => guy) public coolguyz;

  event NFTCreated(uint256 indexed tokenId);

  constructor(string memory newBaseURI, uint256 newMaxSupply)
    ERC721("CoolGuyz", "NFT")
  {
    setBaseURI(newBaseURI);
    setMaxSupply(newMaxSupply);

    // Increment tokenIdCounter so it starts at one
    _tokenIdCounter.increment();
  }

  function getCurrentTokenId() public view returns (uint256) {
    return _tokenIdCounter.current();
  }

  function setPublicPrice(uint256 newPrice) public onlyOwner {
    price = newPrice;
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

  function setWhiteListActive(bool _active) public onlyOwner {
    whiteListActive = _active;
  }

  function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
    merkleRoot = _merkleRoot;
  }


  // Create CoolGuyz
  function _createCoolGuyz(uint256 _tokenId) internal {

    coolguyz[_tokenId].speed = randomFromString(
      string(abi.encodePacked("speed", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].intelligence = randomFromString(
      string(abi.encodePacked("intelligence", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].strength = randomFromString(
      string(abi.encodePacked("strength", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].wisdom = randomFromString(
      string(abi.encodePacked("wisdom", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].defense = randomFromString(
      string(abi.encodePacked("defense", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].agility = randomFromString(
      string(abi.encodePacked("agility", toString(_tokenId))),
      100
    );
    
    coolguyz[_tokenId].charisma = randomFromString(
      string(abi.encodePacked("charisma", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].weight = randomFromString(
      string(abi.encodePacked("weight", toString(_tokenId))),
      100
    );

    coolguyz[_tokenId].height = randomFromString(
      string(abi.encodePacked("height", toString(_tokenId))),
      100
    );

    emit CoolGuyCreated(
      _tokenId,
      coolguyz[_tokenId]
    );
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

  // Mint
  modifier tokenMintable(uint256 tokenId) {
    require(tokenId > 0 && tokenId <= _maxSupply, "Token ID invalid");
    require(price <= msg.value, "Ether value sent is not correct");
    _;
  }

  function _internalMint(address _address) internal returns (uint256) {
    // minting logic
    uint256 current = _tokenIdCounter.current();
    require(current <= _maxSupply, "Max token reached");


    _createCoolGuyz(current);
    _safeMint(_address, current);
    emit NFTCreated(current);
    _tokenIdCounter.increment();

    return current;
  }

  function whiteListMint(bytes32[] calldata _merkleProof, uint256 _num)
    public
    payable
    nonReentrant
  {
    require(whiteListActive, "WhiteList mint is not active");

    address to = _msgSender();
    require(whiteListClaimed[to] + _num <= 10, "Whitelist limit reached");
    require(msg.value >= price * _num, "Ether sent is not enough");


    bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
    require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "Invalid proof");

    uint256 supply = totalSupply();
    require(supply + _num <= _maxSupply, "Exceeds maximum supply");

    for (uint256 i; i < _num; i++) {
      _internalMint(to);
    }

    whiteListClaimed[to] = whiteListClaimed[to] + _num;
  }

  function mint()
    public
    payable
    nonReentrant
    tokenMintable(_tokenIdCounter.current())
  {
    require(!whiteListActive, "Whitelist mint is active");

    address to = _msgSender();
    _internalMint(to);
  }

  function mintMultiple(uint256 _num) public payable {
    require(!whiteListActive, "Whitelist mint is active");

    uint256 supply = totalSupply();
    address to = _msgSender();
    require(_num > 0, "The minimum is one token");
    require(_num <= _maxMintAmount, "You can mint a max of 20 tokens");
    require(supply + _num <= _maxSupply, "Exceeds maximum supply");
    require(msg.value >= price * _num, "Ether sent is not enough");

    for (uint256 i; i < _num; i++) {
      _internalMint(to);
    }
  }

  function ownerMint(uint256 amount, address _address)
    public
    nonReentrant
    onlyOwner
  {
    uint256 supply = totalSupply();
    require(amount > 0, "The minimum is one token");

    require(supply + amount <= _maxSupply, "Exceeds maximum supply");

    for (uint256 i = 1; i <= amount; i++) {
      _internalMint(_address);
    }
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

    function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  // Utilities
  // Returns a random item from the list, always the same for the same token ID
  function pluck(
    uint256 tokenId,
    string memory keyPrefix,
    string[] memory sourceArray
  ) internal view returns (string memory) {
    uint256 rand = randomFromString(
      string(abi.encodePacked(keyPrefix, toString(tokenId))),
      sourceArray.length
    );

    return sourceArray[rand];
  }

  function randomFromString(string memory _salt, uint256 _limit)
    internal
    view
    returns (uint256)
  {
    return
      uint256(
        keccak256(abi.encodePacked(block.number, block.timestamp, _salt))
      ) % _limit;
  }

   function toString(uint256 value) internal pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT license
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

