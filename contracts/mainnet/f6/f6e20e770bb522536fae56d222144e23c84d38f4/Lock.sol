// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract CHVINZ is ERC721, ERC721Enumerable, Pausable, Ownable {
    using Counters for Counters.Counter;
    uint256 maxSupply = 1665;
    uint256 private TOKENS_RESERVED = 0;
    bool public publicMintOpen = false;
    bool public allowListMintOpen = false;
    mapping(address => uint) private walletMints;
    mapping(address => uint256) public balances;
    Counters.Counter private _tokenIdCounter;
    uint256 public constant MAX_TOKENS_PER_TRANSACTION = 5;
    uint public userLimit = 5;
    string public baseURI = "https://ipfs.io/ipfs/Qmf7wiHyZLngG84YMGueyh8zrKqAtTJZqL8TwRh6BAWn3A/";
    string public baseExtenstion = ".json";
    string internal baseTokenUri;

     function setBaseTokenUri(string calldata baseTokenUri_) external onlyOwner {
      baseTokenUri = baseTokenUri_;
  }

  function tokenURI(uint256 tokenId_) public view override returns (string memory) {
      require(_exists(tokenId_), "Token does not exist");
      return string(abi.encodePacked(baseTokenUri, Strings.toString(tokenId_), ".json"));
  }

    constructor() ERC721("CHVINZ", "CHZ") {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }


   function editMintWindows(
        bool _publicMintOpen
    ) external onlyOwner {
        publicMintOpen = _publicMintOpen;
    }



    //add publicMint and AllowListMintOpen Variables
    // require only the allowList people to mint

  

    
   // Add Payment
   // Add Limiting of Supply
    function mint(uint256 quantity) public payable {
        require(publicMintOpen, "Public Mint Closed");
        require(quantity > 0 && quantity <= MAX_TOKENS_PER_TRANSACTION, "Invalid quantity");
        require(msg.value == 0 ether * quantity, "Not Enough ETH");
        require(totalSupply() <= maxSupply, "We Sold Out!");
        require(balanceOf(msg.sender) < userLimit, "Max Mint per wallet reached");
        
        for (uint256 i = 0; i < quantity; i++) {
        uint256 tokenId = _tokenIdCounter.current();    
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId +1);

        }
    }




    function mintOwner() public onlyOwner{
        require(totalSupply() < maxSupply, "SOLD OUT");
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId +1);
    }

    function withdraw(address _addr) external onlyOwner {
        
        uint256 balance = address(this).balance; 
        payable(_addr).transfer(balance);
    }


    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
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
