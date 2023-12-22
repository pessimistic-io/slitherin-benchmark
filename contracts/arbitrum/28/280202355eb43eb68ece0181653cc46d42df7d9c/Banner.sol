// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.13;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";

contract Banner is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public pricePublic;
    uint256 public maxSupply = 250;
    uint256 public maxSaleSupply = 50;
    uint256 private saleCounter;
    bool public isSaleStarted;
    string public baseURI;

    enum SaleStage {
        CLOSED,
        SALE,
        SOLDOUT
    }

    struct Info {
        SaleStage stage;
        uint256 pricePublic;
        uint256 saleCounter;
        uint256 maxSupply;
        uint256 minted;
    }

    mapping(address => uint256) public lastMint;

    constructor(uint256 _pricePublic) ERC721("Arbitrum Ape Yacht Club Banners", "AAYCB")
    {
        pricePublic = _pricePublic;
    }


    function getInfo() public view returns (Info memory) {
        return Info(
            getStage(),
            pricePublic,
            saleCounter,
            maxSupply,
            totalSupply()
        );
    }

    function getStage() public view returns (SaleStage) {
        if (totalSupply() == maxSupply || totalSupply() == maxSaleSupply * saleCounter) {
            return SaleStage.SOLDOUT;
        }
        if (!isSaleStarted) {
            return SaleStage.CLOSED;
        } else {
            return SaleStage.SALE;
        }
    }

    function mintPublic() public payable {
        SaleStage stage = getStage();
        require(stage == SaleStage.SALE, "Sale is closed");
        require(lastMint[msg.sender] < saleCounter, "Maximum per sale exceeded");
        require(msg.value >= pricePublic, "Not enough funds");
        uint256 _tokenId = totalSupply() + 1;
        lastMint[msg.sender] = saleCounter;
        _safeMint(msg.sender, _tokenId);
    }

    function startSale() public onlyOwner {
        isSaleStarted = true;
    }

    function stopSale() public onlyOwner {
        isSaleStarted = false;
    }

    function nextSale() public onlyOwner {
        saleCounter++;
        isSaleStarted = true;
    }

    function setPricePublic(uint256 _newPrice) public onlyOwner {
        pricePublic = _newPrice;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        if (_amount == 0) {
            _amount = address(this).balance;
        }
        payable(msg.sender).transfer(_amount);
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, ((tokenId - 1) % 10 + 1).toString(), ".json")) : '';
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
