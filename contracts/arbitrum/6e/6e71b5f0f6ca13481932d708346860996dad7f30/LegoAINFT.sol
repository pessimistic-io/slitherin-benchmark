// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";

contract LegoAINFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    string public baseTokenURI;
    uint256 public constant MAX_SUPPLY = 6666;
    uint256 public mintPrice = 0.0014 ether;
    uint256 public mintNumber = 6;
    address payable public treasury;

    mapping(address => bool) public minters;
    uint256 public totalMinters = 0;

    constructor(address payable _treasury, string memory _initBaseURI) ERC721("LEGO - AI NFT", "LEGOAI") {
        treasury = _treasury;
        setBaseURI(_initBaseURI);
    }

    event Mint(address indexed user);
    event Whitelist(address indexed user, bool isWhitelist);

    function mintInitialSupply(uint256 _amount) public onlyOwner {
        for(uint i = 0; i < _amount; i++) {
            _mint(msg.sender, totalSupply() + 1);
        }
    }

    function updateTreasury(address payable _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function updateMinPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function mintNFT() public payable nonReentrant {
        require(msg.value == mintPrice, "Incorrect mint price");
        require(balanceOf(msg.sender) + 1 <= mintNumber, "Max NFT limit per user exceeded");
        require(totalSupply() <= MAX_SUPPLY, "Max NFT limit exceeded");

        // Mint the NFT to the sender
        _mint(msg.sender, totalSupply() + 1);

        // If this is a new minter, increment the totalMinters count
        if (!minters[msg.sender]) {
            minters[msg.sender] = true;
            totalMinters++;
        }

        // Transfer the rest to the treasury
        (bool successTreasury, ) = treasury.call{value: msg.value}("");
        require(successTreasury, "Treasury transfer failed.");
        emit Mint(msg.sender);
    }

    function isMinter(address _address) public view returns (bool) {
        return minters[_address];
    }
}

