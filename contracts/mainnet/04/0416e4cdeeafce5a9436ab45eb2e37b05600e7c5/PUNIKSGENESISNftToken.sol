// SPDX-License-Identifier: MIT
/*
01000001 01101010 01101001 01101111 01101110  01001100 01100001 01100010 01110011
 ██▓███   █    ██  ███▄    █  ██▓ ██ ▄█▀  ██████       
▓██░  ██▒ ██  ▓██▒ ██ ▀█   █ ▓██▒ ██▄█▒ ▒██    ▒       
▓██░ ██▓▒▓██  ▒██░▓██  ▀█ ██▒▒██▒▓███▄░ ░ ▓██▄         
▒██▄█▓▒ ▒▓▓█  ░██░▓██▒  ▐▌██▒░██░▓██ █▄   ▒   ██▒      
▒██▒ ░  ░▒▒█████▓ ▒██░   ▓██░░██░▒██▒ █▄▒██████▒▒      
▒▓▒░ ░  ░░▒▓▒ ▒ ▒ ░ ▒░   ▒ ▒ ░▓  ▒ ▒▒ ▓▒▒ ▒▓▒ ▒ ░      
░▒ ░     ░░▒░ ░ ░ ░ ░░   ░ ▒░ ▒ ░░ ░▒ ▒░░ ░▒  ░ ░      
░░        ░░░ ░ ░    ░   ░ ░  ▒ ░░ ░░ ░ ░  ░  ░        
            ░              ░  ░  ░  ░         ░        
                                                       
  ▄████ ▓█████  ███▄    █ ▓█████   ██████  ██▓  ██████ 
 ██▒ ▀█▒▓█   ▀  ██ ▀█   █ ▓█   ▀ ▒██    ▒ ▓██▒▒██    ▒ 
▒██░▄▄▄░▒███   ▓██  ▀█ ██▒▒███   ░ ▓██▄   ▒██▒░ ▓██▄   
░▓█  ██▓▒▓█  ▄ ▓██▒  ▐▌██▒▒▓█  ▄   ▒   ██▒░██░  ▒   ██▒
░▒▓███▀▒░▒████▒▒██░   ▓██░░▒████▒▒██████▒▒░██░▒██████▒▒
 ░▒   ▒ ░░ ▒░ ░░ ▒░   ▒ ▒ ░░ ▒░ ░▒ ▒▓▒ ▒ ░░▓  ▒ ▒▓▒ ▒ ░
  ░   ░  ░ ░  ░░ ░░   ░ ▒░ ░ ░  ░░ ░▒  ░ ░ ▒ ░░ ░▒  ░ ░
░ ░   ░    ░      ░   ░ ░    ░   ░  ░  ░   ▒ ░░  ░  ░  
      ░    ░  ░         ░    ░  ░      ░   ░        ░  
01000001 01101010 01101001 01101111 01101110  01001100 01100001 01100010 01110011                                                       
*/
pragma solidity >=0.8.19 <0.9.0;

import "./ERC721AQueryable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

contract PUNIKSGENESISNftToken is ERC721AQueryable, Ownable, ReentrancyGuard {
  using Strings for uint256;

  string public uriPrefix = "";
  string public uriSuffix = ".json";

  uint256 public cost;
  uint256 public maxSupply;
  uint256 public maxMintAmountPerTx;

  bool public paused = true;
  bool public locked = false;

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
    require(
      _mintAmount > 0 && _mintAmount <= maxMintAmountPerTx,
      "Invalid mint amount!"
    );
    require(totalSupply() + _mintAmount <= maxSupply, "Max supply exceeded!");
    _;
  }

  modifier mintPriceCompliance(uint256 _mintAmount) {
    require(msg.value >= cost * _mintAmount, "Insufficient funds!");
    _;
  }

  function mint(
    uint256 _mintAmount
  )
    public
    payable
    mintCompliance(_mintAmount)
    mintPriceCompliance(_mintAmount)
  {
    require(!paused, "The contract is paused!");

    _safeMint(_msgSender(), _mintAmount);
  }

  function mintForAddress(
    uint256 _mintAmount,
    address _receiver
  ) public mintCompliance(_mintAmount) onlyOwner {
    _safeMint(_receiver, _mintAmount);
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(
    uint256 _tokenId
  ) public view virtual override(ERC721A, IERC721A) returns (string memory) {
    require(
      _exists(_tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );

    string memory currentBaseURI = _baseURI();
    return
      bytes(currentBaseURI).length > 0
        ? string(
          abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix)
        )
        : "";
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setMaxSupply(uint256 _maxSupply) public onlyOwner {
    require(!locked, "Max supply is locked!");
    maxSupply = _maxSupply;
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

  function setLocked(bool _lock) public onlyOwner {
    require(!locked, "Max supply is locked!");
    locked = _lock;
  }

  function withdraw() public onlyOwner nonReentrant {
    // This will transfer the remaining contract balance to the owner.
    // Do not remove this otherwise you will not be able to withdraw the funds.
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: address(this).balance}("");
    require(os);
    // =============================================================================
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }
}

