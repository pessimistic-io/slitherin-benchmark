// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./AggregatorV3Interface.sol";
import "./ERC721Enumerable.sol";
import "./IERC2981.sol";

error ArbitrumNFT_OnlyOwnerCanCall();
error ArbitrumNFT_NotEnoughBalanceToWithdraw();
error ArbitrumNFT_TransferFailed();
error ArbitrumNFT_PriceNotMatched(uint256 price);
error ArbitrumNFT_SimilarToCurrentPrice(uint256 currentPrice);
error ArbitrumNFT_SimilarToCurrentBaseURI(string currentBaseURI);
error ArbitrumNFT_InvalidOption(uint256 a, uint256 b, uint256 c);

contract MYHERBX is ERC721Enumerable, IERC2981, Ownable {
    /////////////////////////State Varaibles///////////////////////////////////
    AggregatorV3Interface internal priceFeed;
    string private baseURI;
    uint256 public priceOfCat1;
    uint256 public priceOfCat2;
    uint256 public priceOfCat3;
    uint256 public royalty = 100;

    /////////////////////////Mapping///////////////////////////////////
    mapping(uint256 => string) private _tokenURIs;

    /////////////////////////Events///////////////////////////////////
    event NFTMinted(address indexed user, uint256 indexed tokenId);

    constructor(
        string memory _uri,
        uint256 _priceOfCat1,
        uint256 _priceOfCat2,
        uint256 _priceOfCat3
    ) ERC721("MYHERBX.COM", "Herbx") {
        baseURI = _uri;
        priceOfCat1 = _priceOfCat1;
        priceOfCat2 = _priceOfCat2;
        priceOfCat3 = _priceOfCat3;
        priceFeed = AggregatorV3Interface(
            0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612 // arb
        );
    }

    /////////////////////////Main Functions///////////////////////////////////

    function _setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) internal virtual {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
    }

    function buyNFT(string calldata data, uint256 _opt) public payable {
        if (_opt == 1) {
            if (msg.value < getPrice(priceOfCat1)) {
                revert ArbitrumNFT_PriceNotMatched(getPrice(priceOfCat1));
            }
        } else if (_opt == 2) {
            if (msg.value < getPrice(priceOfCat2)) {
                revert ArbitrumNFT_PriceNotMatched(getPrice(priceOfCat2));
            }
        } else if (_opt == 3) {
            if (msg.value < getPrice(priceOfCat3)) {
                revert ArbitrumNFT_PriceNotMatched(getPrice(priceOfCat3));
            }
        } else {
            revert ArbitrumNFT_InvalidOption(1, 2, 3);
        }

        uint256 mintIndex = totalSupply() + 10001;
        _safeMint(_msgSender(), mintIndex);
        _setTokenURI(mintIndex, data);

        emit NFTMinted(_msgSender(), mintIndex);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /////////////////////////OnlyOwner Functions///////////////////////////////////

    function setPrice(uint256 _price, uint256 _opt) public onlyOwner {
        if (_opt == 1) {
            if (priceOfCat1 == _price) {
                revert ArbitrumNFT_SimilarToCurrentPrice(priceOfCat1);
            }

            priceOfCat1 = _price;
        } else if (_opt == 2) {
            if (priceOfCat2 == _price) {
                revert ArbitrumNFT_SimilarToCurrentPrice(priceOfCat2);
            }
            priceOfCat2 = _price;
        } else if (_opt == 3) {
            if (priceOfCat3 == _price) {
                revert ArbitrumNFT_SimilarToCurrentPrice(priceOfCat3);
            }
            priceOfCat3 = _price;
        } else {
            revert ArbitrumNFT_InvalidOption(1, 2, 3);
        }
    }

    function setBaseURI(string memory _uri) public onlyOwner {
        if (
            keccak256(abi.encodePacked(baseURI)) ==
            keccak256(abi.encodePacked(_uri))
        ) {
            revert ArbitrumNFT_SimilarToCurrentBaseURI(baseURI);
        }

        baseURI = _uri;
    }

    function withdraw() public onlyOwner returns (bool) {
        if (address(this).balance == 0) {
            revert ArbitrumNFT_NotEnoughBalanceToWithdraw();
        }
        (bool success, ) = payable(_msgSender()).call{
            value: address(this).balance
        }("");
        if (!success) {
            revert ArbitrumNFT_TransferFailed();
        }
        return true;
    }

    /////////////////////////View Functions///////////////////////////////////

    function getLatestPrice() internal view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function getPrice(uint256 _price) public view returns (uint256) {
        uint256 temp = uint256(getLatestPrice());
        uint256 price = (((_price * 10 ** 18) / temp) * 10 ** 8);
        return price;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI query for nonexistent token"
        );

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Enumerable, IERC165) returns (bool) {
        return (interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId));
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function royaltyInfo(
        uint256 /*_tokenId*/,
        uint256 _salePrice
    )
        external
        view
        override(IERC2981)
        returns (address Receiver, uint256 royaltyAmount)
    {
        return (owner(), (_salePrice * royalty) / 1000); //100*10 = 1000
    }
}

