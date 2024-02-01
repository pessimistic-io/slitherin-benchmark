// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./DefaultOperatorFilterer.sol";
import "./ERC721ABurnable.sol";

contract OrdinalBabyApes is ERC721A, Ownable, ERC721ABurnable, DefaultOperatorFilterer {
    bool public isSale = false;
    bool public isBurn = false;

    uint256 public max_supply = 5555;
    uint256 public price = 0.003 ether;
    uint256 public per_wallet = 10;
    uint256 public free_per_wallet = 1;

    // mapping(address => uint) public burntBy;
    string private baseUri;

    constructor(string memory _baseUri) ERC721A("OrdinalBabyApes", "OBA") {
        baseUri = _baseUri;
        _mint(msg.sender, 1);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function flipSaleState() external onlyOwner {
        isSale = !isSale;
    }

    function flipBurnState() external onlyOwner {
        isBurn = !isBurn;
    }

    function withdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function mint(uint256 quantity) external payable {
        require(isSale, "Sale has not started yet");
        require(msg.sender == tx.origin, "No contracts allowed");

        require(balanceOf(msg.sender) + quantity < per_wallet, "Mint limit reached for this wallet");
        require(totalSupply() + quantity < max_supply, "Not enough NFTs left to mint");

        if (balanceOf(msg.sender) == 0) {
            require(price * (quantity - free_per_wallet) <= msg.value, "Insufficient funds sent");
        } else 
            {require(price * quantity <= msg.value, "Insufficient funds sent");
        }
        
        _mint(msg.sender, quantity);
    }

    function mintForAddress(uint256 amount, address receiver) external onlyOwner {
        require(totalSupply() + amount <= max_supply,"Not enough NFTs left to mint");
        _mint(receiver, amount);
    }

    function burn(uint256 tokenId) public virtual override {
        require(isBurn, "Burn is not enabled");
        // burntBy[msg.sender] += 1;
        _burn(tokenId, true);
    }

    function burnTokens(uint256[] calldata tokenIds) public {
        require(isBurn, "Burn is not enabled");
        uint256 amount = tokenIds.length;

        for (uint256 i = 0; i < amount;) {
            _burn(tokenIds[i]);
            unchecked { ++i; }
        }
        // burntBy[msg.sender] += amount;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setPerWallet(uint256 _per) external onlyOwner {
        per_wallet = _per;
    }

    function setFreePerWallet(uint256 _per) external onlyOwner {
        free_per_wallet = _per;
    }

    function setBaseURI(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;
    }

    ////////////////////////
    //operator
    ////////////////////////

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721A, IERC721A) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}
