//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";
import "./ERC721A.sol";

contract TestNFT is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;
    string public baseURI;

    uint256 public maxSupply = 48000;
    uint256 public maxMintPerWallet = 10;
    uint256 public totalFreeMinted;

    bool public mintEnabled = false;

    mapping(address => bool) public mintedFree;

    constructor() ERC721A("TEST NFT", "TEST") {}

    modifier mintCompliance(uint256 _quantity) {
        require(mintEnabled, "Mint not Live yet");
        require(_quantity >= 1, "Enter the correct quantity");
        require(_quantity + _numberMinted(msg.sender) <= maxMintPerWallet, "Mint limit exceeded");
        require(_quantity + totalSupply() <= maxSupply, "Sold Out!");
        
        _;
    }

    function _baseURI() internal view virtual override returns(string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _baseTokenURI) external onlyOwner {
        baseURI = _baseTokenURI;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns(string memory) {
        require(_exists(_tokenId), "Invalid TokenId");
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), ".json"))
        : "";
    }

    function mint(uint256 _quantity) external payable mintCompliance(_quantity) {
        totalFreeMinted += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    function teamMint(uint256 _quantity) external payable onlyOwner{
        require(_quantity <= 155, "limit exceeded");
        _safeMint(msg.sender, _quantity);
    }

    function setMintEnabled() external onlyOwner {
        mintEnabled = !mintEnabled;
    }

    function setMaxMintPerWallet(uint256 _maxMintPerWallet) external onlyOwner {
        maxMintPerWallet = _maxMintPerWallet; 
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function withdrawETH() external onlyOwner nonReentrant {
        (bool sent, ) = payable(owner()).call{ value: address(this).balance }("");
        require(sent, "Failed Transaction");
    }

    receive() external payable {}
}
