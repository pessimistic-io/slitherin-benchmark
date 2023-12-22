// SPDX-License-Identifier: MIT
// Author: @yourbestdev
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ERC721URIStorage.sol";

contract ProductMarketplace is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;

    mapping(uint256 => ProductItem) private idToProductItem;

    struct ProductItem {
        uint256 tokenId;
        uint256 productId;
        uint256 price;
        address buyer;
        string tokenUri;
    }

    event ProductItemMinted(
        uint256 indexed tokenId,
        uint256 indexed productId,
        uint256 price,
        uint256 paymentTokenId
    );

    address[] public paymentTokens;

    constructor(address[] memory _paymentTokens) ERC721("NFT Bay", "NFTB") {
        paymentTokens = _paymentTokens;
    }

    receive() external payable {}

    /* Mints a token and lists it in the marketplace */
    function createToken(
        string memory tokenURI,
        uint256 productId,
        uint256 paymentTokenId,
        uint256 _price
    ) public payable returns (uint256) {
        _tokenIds.increment();
        uint256 price = 0;
        uint256 newTokenId = _tokenIds.current();
        if (msg.value > 0) price = msg.value;
        else {
            require(
                paymentTokenId < paymentTokens.length,
                "Invalid Payment Token"
            );
            address paymentAddress = paymentTokens[paymentTokenId];
            IERC20 token = IERC20(paymentAddress);
            price = _price;
            token.transferFrom(msg.sender, address(this), price);
        }

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        createProductItem(
            newTokenId,
            productId,
            price,
            tokenURI,
            paymentTokenId
        );
        return newTokenId;
    }

    function createProductItem(
        uint256 tokenId,
        uint256 productId,
        uint256 price,
        string memory tokenURI,
        uint256 paymentTokenId
    ) private {
        require(price > 0, "Price must be at least 1 wei");

        idToProductItem[tokenId] = ProductItem(
            tokenId,
            productId,
            price,
            payable(msg.sender),
            tokenURI
        );

        // _transfer(msg.sender, address(this), tokenId);
        emit ProductItemMinted(tokenId, productId, price, paymentTokenId);
    }

    /* Returns only items that a user has purchased */
    function fetchMyNFTs() public view returns (ProductItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToProductItem[i + 1].buyer == msg.sender) {
                itemCount += 1;
            }
        }

        ProductItem[] memory items = new ProductItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToProductItem[i + 1].buyer == msg.sender) {
                uint256 currentId = i + 1;
                ProductItem storage currentItem = idToProductItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    function fetchProductItem(
        uint256 tokenId
    ) public view returns (ProductItem memory) {
        return idToProductItem[tokenId];
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawBalance() public onlyOwner {
        (bool success, ) = address(owner()).call{value: getBalance()}("");
        require(success, "Transfer failed.");
    }

    function withdrawERC20Balance(address _erc20) public onlyOwner {
        IERC20 token = IERC20(_erc20);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        require(
            from == address(0) || from == owner(),
            "Only adminitrator can trasfer tokens"
        );
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}

