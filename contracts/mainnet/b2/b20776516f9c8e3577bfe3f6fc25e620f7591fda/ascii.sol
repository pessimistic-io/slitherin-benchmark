// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./OperatorFilterer.sol";
import "./ERC2981.sol";

contract ascii is ERC721A, ERC2981, OperatorFilterer, Ownable {
    using Strings for uint256;
    string  public baseURI;
    uint256 public constant maxSupply         = 10000;
    uint256 public constant maxFree           = 1;
    uint256 public price                      = 0.005 ether;
    uint256 public maxPerTx                   = 10;
    uint256 public maxPerWallet               = 10;
    uint256 public totalFree                  = 10000;
    uint256 public freeMintCount              = 0;
    bool    public mintEnabled                = false;
    bool    public revealed                   = false;

    mapping(address => uint256) public _freeMints;
    mapping(address => uint256) public _walletMints;

    address public constant w1 = 0x56083cc154dFcAFF136f41d768993B1f28c341Ac;
    constructor() ERC721A("ASCII", "AC"){
        _setDefaultRoyalty(msg.sender, 500);
        _registerForOperatorFiltering();
    }

    function mint(uint256 amount) external payable {
        require(mintEnabled, "Mint is not live yet");
        require(totalSupply() + amount <= maxSupply, "megadiezone full");
        require(amount <= maxPerTx, "Too many per tx");
        require(_walletMints[msg.sender] + amount <= maxPerWallet, "Too many per wallet");
        require(msg.sender == tx.origin, "No contracts");
        uint256 cost = price;
        uint256 freeLeft = maxFree - _freeMints[msg.sender];
        bool isFree = ((freeMintCount + freeLeft <= totalFree) && (_freeMints[msg.sender] < maxFree));

        if (isFree) { 
            if(amount >= freeLeft) {
                uint256 paid = amount - freeLeft;
                require(msg.value >= (paid * cost), "Not enough ETH");
                _freeMints[msg.sender] = maxFree;
                freeMintCount += freeLeft;
            } else if (amount < freeLeft) {
                require(msg.value >= 0, "Not enough ETH");
                _freeMints[msg.sender] += amount;
                freeMintCount += amount;
            }
        } else {
            require(msg.value >= amount * cost, "Not enough ETH");
        }
        
        _walletMints[msg.sender] += amount;
        _safeMint(msg.sender, amount);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");

        if (!revealed) {
            return "https://gateway.pinata.cloud/ipfs/QmNVc2Hk1tsaFKCCeYaFtq2e7TG1tD1ufNgQTdN8tfvJfU/0";
        }
	    string memory currentBaseURI = _baseURI();
	    return bytes(currentBaseURI).length > 0	? string(abi.encodePacked(currentBaseURI, tokenId.toString())) : "";
    }
    
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseUri(string memory baseuri_) public onlyOwner {
        baseURI = baseuri_;
    }

    function setPrice(uint256 price_) external onlyOwner {
        price = price_;
    }

    function setMaxTotalFree(uint256 MaxTotalFree_) external onlyOwner {
        totalFree = MaxTotalFree_;
    }

    function toggleMinting() external onlyOwner {
        mintEnabled = !mintEnabled;
    }
    function Airdrop(address _address, uint256 _amount) external onlyOwner {
        require(
            totalSupply() + _amount <= 6000,
            "Can't Airdrop more than max supply"
        );
        _mint(_address, _amount);
    }

    function reveal(bool _state) public onlyOwner {
        revealed = _state;
    }

    function reserve(uint256 tokens) external onlyOwner {
        require(totalSupply() + tokens <= maxSupply, "Minting would exceed max supply");
        require(tokens > 0, "Must mint at least one");
        require(_walletMints[_msgSender()] + tokens <= 69, "Can only reserve 69 tokens");

        _walletMints[_msgSender()] += tokens;
        _safeMint(_msgSender(), tokens);
    }

    function withdrawAll() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Insufficent balance");
        _withdraw(w1, ((balance * 100) / 100));
    }

    function _withdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Failed to withdraw Ether");
    }

    function setRoyaltyInfo(address payable receiver, uint96 numerator) public onlyOwner {
        _setDefaultRoyalty(receiver, numerator);
    }
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC2981) returns (bool) {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }    
}
