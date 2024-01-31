// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./ERC721AQueryable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./DefaultOperatorFilterer.sol";

contract DayNNight is ERC721A, Ownable, ReentrancyGuard, DefaultOperatorFilterer {
  using Strings for uint256;
  bool public paused = false;
  bool public revealed = true;
  string public uriPrefix = 'ipfs://QmUPfSXP9GsKhQxcdSTCQk97j4qzpXmYTTiguxWaRPNWs2/';
  string public uriSuffix = '.json';
  uint256 public cost;
  uint256 public maxSupply;
  uint256 public freeLeft = 300;
  mapping(address => uint256) public freeMapping;
  uint256 public freePerTransaction = 1;
  uint256 public freePerPerson = 1;
  uint256 public maxMintAmountPerTx;

  constructor(
    string memory _tokenName,
    string memory _tokenSymbol,
    uint256 _cost,
    uint256 _maxSupply,
    uint256 _maxMintAmountPerTx
  ) ERC721A(_tokenName, _tokenSymbol) {
    setCost(_cost);
    maxSupply = _maxSupply;
    setMaxMintAmountPerTx(_maxMintAmountPerTx);
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, 'Invalid mint amount!');
    require(totalSupply() + _mintAmount <= maxSupply, 'Max supply exceeded!');

    if (msg.value < cost * _mintAmount) {
      require(freeLeft > 0, "Free supply is depleted");
      require(_mintAmount < freePerTransaction + 1, 'Too many free tokens at a time');
      require(freeMapping[msg.sender] + _mintAmount < freePerPerson + 1, 'Too many free tokens claimed');
    } else {
      require(msg.value >= cost * _mintAmount, 'Insufficient funds!');
    }
    _;
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {
    require(!paused, 'The contract is paused!');
    require(tx.origin == msg.sender, "Contracts not allowed to mint.");
    if (msg.value < cost * _mintAmount) {
      freeLeft -= _mintAmount;
      freeMapping[msg.sender] += _mintAmount;
    }
    _safeMint(_msgSender(), _mintAmount);
  }
  
  function mintForAddress(uint256 _mintAmount, address _receiver) public onlyOwner {
    _safeMint(_receiver, _mintAmount);
  }

  function teamMint(uint quantity) public onlyOwner {
    require(quantity > 0, "Invalid mint amount");
    require(totalSupply() + quantity <= maxSupply, "Maximum supply exceeded");
    _safeMint(msg.sender, quantity);
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), 'ERC721Metadata: URI query for nonexistent token');

    if (!revealed) {
      return _baseURI();
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : '';
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setFree(uint256 _amount) public onlyOwner {
    freeLeft = _amount;
  }

  function setfreePerPerson(uint256 _amount) public onlyOwner {
    freePerPerson = _amount;
  }

  function setfreePerTransaction(uint256 _amount) public onlyOwner {
    freePerTransaction = _amount;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
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

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }

  function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
    super.transferFrom(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId, data);
  }

  function withdraw() public onlyOwner nonReentrant {
    (bool os, ) = payable(owner()).call{value: address(this).balance}('');
    require(os);
  }
}
