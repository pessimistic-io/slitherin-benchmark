// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// Contracts
import "./ERC721Enumerable.sol";
import "./Ownable.sol";

contract MithicalNFT is ERC721Enumerable, Ownable {
  using Strings for uint256;

  string public baseURI;
  string public baseExtension = ".json";
  address public minter;
  bool public revealed = false;
  uint256 public maxSupply = 1000;

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _initBaseURI,
    address _minter
  ) ERC721(_name, _symbol) {
    baseURI = _initBaseURI;
    mint(msg.sender, 25);
    minter = _minter;
  }

  //only owner
  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    require(!revealed, "Cannot change baseURI after minting");
    baseURI = _newBaseURI;
    revealed = true;
  }

  function setMinter(address _minter) public onlyOwner {
    minter = _minter;
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension;
  }

  // internal
  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }

  function mint(address _to, uint256 _mintAmount) private {
    uint256 supply = totalSupply();
    require(_mintAmount > 0, "mint amount 0");
    require(
      supply + _mintAmount <= maxSupply,
      "mint amount exceeds max supply"
    );

    for (uint256 i = 1; i <= _mintAmount; i++) {
      _safeMint(_to, supply + i);
    }
  }

  function minterMint(address _to, uint256 _mintAmount)
    external
    onlyMinter
    returns (bool)
  {
    uint256 supply = totalSupply();
    require(_mintAmount > 0, "mint amount 0");
    require(
      supply + _mintAmount <= maxSupply,
      "mint amount exceeds max supply"
    );
    for (uint256 i = 1; i <= _mintAmount; i++) {
      _safeMint(_to, supply + i);
    }
    return true;
  }

  // public

  function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokenIds;
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );

    string memory currentBaseURI = _baseURI();
    return
      bytes(currentBaseURI).length > 0
        ? string(
          abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)
        )
        : "";
  }

  modifier onlyMinter() {
    require(msg.sender == minter, "only minter contract can mint");
    _;
  }
}

