// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";

contract SkullGodesses is ERC721A, Ownable, ReentrancyGuard {
  using Address for address;
  using Strings for uint;

  string  public  baseTokenURI = "https://mypinata.space/ipfs/QmVYQAK2TS7WnXMCbHEsWAe1QKe3QboEpidWPRJG9MchqM";

  uint256 public maxSupply = 555;
  uint256 public  MAX_MINTS_PER_TX = 1;
  uint256 public FREE_MINTS = 200;
  uint256 public  PUBLIC_SALE_PRICE = 0.005 ether;

  bool public isPublicSaleActive = true;

  constructor(

  ) ERC721A("Skull Godesses", "Skull Godesses") {

  }

  function publicMint(uint256 numberOfTokens)
      external
      payable
  {
    require(isPublicSaleActive, "Public sale is not open");
    require(numberOfTokens <= MAX_MINTS_PER_TX, "Max 1 per transaction");
    require(
      totalSupply() + numberOfTokens <= maxSupply,
      "Maximum supply exceeded"
    );
    uint256 price = PUBLIC_SALE_PRICE;
    if (totalSupply() + numberOfTokens <= FREE_MINTS) {
      price = 0;
    }
    require(msg.value >= price * numberOfTokens, "insufficient eth");
    _safeMint(msg.sender, numberOfTokens);
  }

  function setBaseURI(string memory baseURI)
    public
    onlyOwner
  {
    baseTokenURI = baseURI;
  }

  function treasuryMint(uint quantity, address user)
    public
    onlyOwner
  {
    require(
      quantity > 0,
      "Invalid mint amount"
    );
    require(
      totalSupply() + quantity <= maxSupply,
      "Maximum supply exceeded"
    );
    _safeMint(user, quantity);
  }

  function withdraw()
    public
    onlyOwner
    nonReentrant
  {
    Address.sendValue(payable(msg.sender), address(this).balance);
  }

  function tokenURI(uint _tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(_tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );
    return string(abi.encodePacked(baseTokenURI, "/", _tokenId.toString(), ".json"));
  }

  function _baseURI()
    internal
    view
    virtual
    override
    returns (string memory)
  {
    return baseTokenURI;
  }

  function setIsPublicSaleActive(bool _isPublicSaleActive)
      external
      onlyOwner
  {
      isPublicSaleActive = _isPublicSaleActive;
  }

  function setSalePrice(uint256 _price)
      external
      onlyOwner
  {
      PUBLIC_SALE_PRICE = _price;
  }

  function setMaxLimitPerTransaction(uint256 _limit)
      external
      onlyOwner
  {
      MAX_MINTS_PER_TX = _limit;
  }

}
