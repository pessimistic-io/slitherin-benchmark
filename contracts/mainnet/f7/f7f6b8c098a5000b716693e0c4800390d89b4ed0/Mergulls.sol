// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./ERC721AQueryable.sol";
import "./IERC721A.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract Mergulls is ERC721AQueryable, Ownable, ReentrancyGuard {
  using Strings for uint256;

  string public uriPrefix = '';
  string public uriSuffix = '.json';
  string public hiddenMetadataUri;
  
  uint256 public cost;
  uint256 public maxSupply;
  uint256 public maxMintAmountPerTx;

  bool public paused = true;
  bool public revealed = false;

  constructor() ERC721A('Mergulls', 'MGLS') {
    maxSupply = 1000;
    setCost(0.1 ether);
    setMaxMintAmountPerTx(10);
    setHiddenMetadataUri('https://mint.wanderingsailors.com/tokens/hidden/hidden.json');

    _safeMint(0x6219C7a46F819c73563E1F4deF23078B827E725c, 1);
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, 'Invalid mint amount!');
    require(totalSupply() + _mintAmount <= maxSupply, 'Max supply exceeded!');
    _;
  }

  modifier mintPriceCompliance(uint256 _mintAmount) {
    require(msg.value >= cost * _mintAmount, 'Insufficient funds!');
    _;
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
    require(!paused, 'The contract is paused!');

    _safeMint(_msgSender(), _mintAmount);
  }

  function mintForAddress(uint256 _mintAmount, address _receiver) public payable mintCompliance(_mintAmount) onlyOwner {
    // This will pay HashLips Lab Team 5% of the initial sale.
    // By leaving the following lines as they are you will contribute to the
    // development of tools like this and many others.
    // =============================================================================
    uint256 hlContribution = cost * _mintAmount * 5 / 100;
    require(msg.value >= hlContribution, 'Insufficient funds!');
    (bool hs, ) = payable(0x146FB9c3b2C13BA88c6945A759EbFa95127486F4).call{value: hlContribution}('');
    require(hs);
    // =============================================================================

    _safeMint(_receiver, _mintAmount);
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), 'ERC721Metadata: URI query for nonexistent token');

    if (revealed == false) {
      return hiddenMetadataUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : '';
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setHiddenMetadataUri(string memory _hiddenMetadataUri) public onlyOwner {
    hiddenMetadataUri = _hiddenMetadataUri;
  }

  function setUriPrefix(string memory _uriPrefix) public onlyOwner {
    uriPrefix = _uriPrefix;
  }

  function setUriSuffix(string memory _uriSuffix) public onlyOwner {
    uriSuffix = _uriSuffix;
  }

  function setPaused(bool _state) public onlyOwner {
    paused = _state;
  }

  function withdraw() public onlyOwner nonReentrant {
    // This will pay HashLips Lab Team 5% of the initial sale.
    // By leaving the following lines as they are you will contribute to the
    // development of tools like this and many others.
    // =============================================================================
    (bool hs, ) = payable(0x146FB9c3b2C13BA88c6945A759EbFa95127486F4).call{value: address(this).balance * 5 / 100}('');
    require(hs);
    // =============================================================================

    // This will transfer the remaining contract balance to the owner.
    // Do not remove this otherwise you will not be able to withdraw the funds.
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: address(this).balance}('');
    require(os);
    // =============================================================================
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }

  // WGG Free Claim
  struct WggTokenData {
    uint256 tokenId;
    address owner;
    bool hasClaimed;
  }

  event WggFreeClaim(uint256 indexed tokenId, address indexed from);

  IERC721A constant public WGG = IERC721A(0x67bF1767b48Df071B84B877dffBBD2e60006C6E3);
  mapping(uint256 => bool) public wggClaimed;

  function getWggTokensData(uint256 _startId, uint256 _endId) public view returns (WggTokenData[] memory) {
    if (_endId == 0) {
      _endId = WGG.totalSupply();
    }

    uint256 resultLength = _endId - _startId + 1;
    WggTokenData[] memory tokensData = new WggTokenData[](resultLength);

    for (uint i = 0; i < resultLength; i++) {
      uint256 currentTokenId = i + _startId;

      tokensData[i] = WggTokenData(
        currentTokenId,
        WGG.ownerOf(currentTokenId),
        wggClaimed[currentTokenId]
      );
    }

    return tokensData;
  }

  function wggFreeClaim(uint256[] memory _tokenIds) public mintCompliance(_tokenIds.length / 2) {
    require(!paused, 'The contract is paused!');

    uint256 mintAmount = _tokenIds.length / 2;
    uint256 requiredTokensAmount = mintAmount * 2;

    for (uint256 i = 0; i < requiredTokensAmount; i++) {
      uint256 tokenId = _tokenIds[i];

      require(WGG.ownerOf(tokenId) == msg.sender, 'You must be the owner of the given tokens!');

      require(wggClaimed[tokenId] != true, 'One or more tokens have already been used to claim!');

      wggClaimed[tokenId] = true;

      emit WggFreeClaim(tokenId, msg.sender);
    }

    _safeMint(msg.sender, mintAmount);
  }
}

