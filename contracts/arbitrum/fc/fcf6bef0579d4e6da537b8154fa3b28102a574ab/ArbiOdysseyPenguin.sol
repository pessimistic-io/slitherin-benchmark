// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ERC721A.sol";
import "./Ownable.sol";

contract ArbiOdysseyPenguins is ERC721A, Ownable {
  using Strings for uint256;

  string public baseURI;
  string public baseExtension = ".json";
  uint256 public cost = 2000000000000000;
  uint256 public maxSupply = 10000;
  uint256 public limitPerTX = 10;
  bool public publicsale = false;

  constructor() ERC721A("Arbi Odyssey Penguins", "AOP") {
    setBaseURI("ipfs://QmQF4sBo4YWv8wTyedG3QK6vJrP7vpibxW2srm5GxKaXYW/");
  }

  // ====== Settings ======
  modifier callerIsUser() {
    require(tx.origin == msg.sender, "Cannot be called by a contract");
    _;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }
  
  function _startTokenId() internal pure override returns (uint256){
    return 1;
  }
  //

  // ====== Public ======
  function mint(uint256 _mintAmount) public payable callerIsUser {
    // Is publicsale active
    require(publicsale, "publicsale is not active");
    //

    // Amount and payment control
    uint256 supply = totalSupply();
    require(_mintAmount <= limitPerTX, "maximum mint per transaction is exceeded");
    require(_mintAmount > 0, "need to mint at least 1 NFT");
    require(supply + _mintAmount <= maxSupply, "max NFT limit exceeded");
    require(msg.value >= cost * _mintAmount, "insufficient funds");
    //

    _safeMint(msg.sender, _mintAmount);
  }

  // ====== Owner ======
  function ownerMint(uint256 _mintAmount) public onlyOwner {
    // Amount Control
    uint256 supply = totalSupply();
    require(_mintAmount > 0, "need to mint at least 1 NFT");
    require(supply + _mintAmount <= maxSupply, "max NFT limit exceeded");
    //

    _safeMint(msg.sender, _mintAmount);
  }

  // ====== View ======
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
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
  }

  /// @dev Returns the tokenIds of the address. O(totalSupply) in complexity.
  function tokensOfOwner(address owner) external view returns (uint256[] memory) {
    unchecked {
        uint256[] memory a = new uint256[](balanceOf(owner)); 
        uint256 end = _currentIndex;
        uint256 tokenIdsIdx;
        address currOwnershipAddr;
        for (uint256 i; i < end; i++) {
            TokenOwnership memory ownership = _ownerships[i];
            if (ownership.burned) {
                continue;
            }
            if (ownership.addr != address(0)) {
                currOwnershipAddr = ownership.addr;
            }
            if (currOwnershipAddr == owner) {
                a[tokenIdsIdx++] = i;
            }
        }
        return a;    
    }
  }

  // ====== Only Owner ======
  // Cost and Limit
  function setCost(uint256 _newCost) public onlyOwner {
    cost = _newCost;
  }

  function setMaxPublicSaleMint(uint256 _newLimitPerTX) public onlyOwner {
    limitPerTX = _newLimitPerTX;
  }
  //

  // Metadata
  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    baseURI = _newBaseURI;
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension;
  }
  //

  // Sale State
  function setPublicsale() public onlyOwner {
    publicsale = !publicsale;
  }
  //
 
  function withdraw() public payable onlyOwner {
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: address(this).balance}("");
    require(os);
    // =============================================================================
  }
}
