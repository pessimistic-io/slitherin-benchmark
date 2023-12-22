// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BaseERC721A.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IERC2981.sol";

contract TFTrademark is BaseERC721A {
    using Strings for uint256;

    string private _contractBaseURI;
    string private _contractURI;

    struct TrademarkData {
        uint256 duration;
        uint256 rentEndTimestamp;
        address royaltyReceiver;
        uint256 royaltyBps;
    }

    mapping(uint256 => TrademarkData) public trademarkData;

    event DurationSet(uint256 tokenId, uint256 duration);
    event DurationSetRange(
        uint256 firstTokenId,
        uint256 lastTokenId,
        uint256 duration
    );

    event RentStart(
        uint256 tokenId,
        uint256 duration,
        uint256 rentEndTimestamp
    );
    event Revoke(uint256 tokenId);

    constructor(
        string memory name,
        string memory symbol,
        string memory contractBaseURI,
        string memory contracMetadataURI
    ) BaseERC721A(name, symbol) {
        _contractBaseURI = contractBaseURI;
        _contractURI = contracMetadataURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _contractBaseURI = newBaseURI;
    }

    function setContractURI(string memory newuri) external onlyOwner {
        _contractURI = newuri;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _contractBaseURI;
    }

    function adminMint(
        address receiver,
        uint256 qty,
        uint256 duration,
        address royaltyReceiver,
        uint256 royaltyBps
    ) external onlyOwner {
        uint256 firstMintedId = _totalMinted() + _startTokenId();
        _safeMint(receiver, qty);
        for (uint256 i = firstMintedId; i <= _totalMinted(); i++) {
            trademarkData[i] = TrademarkData(
                duration,
                0,
                royaltyReceiver,
                royaltyBps
            );
        }
        emit DurationSetRange(firstMintedId, _totalMinted(), duration);
    }

    function setDuration(
        uint256 tokenId,
        uint256 newDuration
    ) external onlyOwner {
        require(trademarkData[tokenId].rentEndTimestamp == 0, "NFT is in rent");
        trademarkData[tokenId].duration = newDuration;
        emit DurationSet(tokenId, newDuration);
    }

    function setDurationRange(
        uint256 startId,
        uint256 endId,
        uint256 newDuration
    ) external onlyOwner {
        for (uint256 i = startId; i <= endId; i++) {
            require(trademarkData[i].rentEndTimestamp == 0, "NFT is in rent");
            trademarkData[i].duration = newDuration;
        }
        emit DurationSetRange(startId, endId, newDuration);
    }

    function revoke(uint256 tokenId) external onlyOwner {
        require(
            trademarkData[tokenId].rentEndTimestamp <= block.timestamp,
            "NFT is in rent"
        );
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
        trademarkData[tokenId].rentEndTimestamp = 0;

        emit Revoke(tokenId);
    }

    function burn(uint256 tokenId) public override onlyOwner {
        _burn(tokenId);
        trademarkData[tokenId].duration = 0;
        trademarkData[tokenId].rentEndTimestamp = 0;
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        uint256 rentEndTimestamp = trademarkData[startTokenId].rentEndTimestamp;
        if (rentEndTimestamp < block.timestamp && rentEndTimestamp > 0) {
            require(
                msg.sender == owner(),
                "Only owner can move NFT after rent"
            );
        }
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        if (
            from != address(0) &&
            to != address(0) &&
            trademarkData[startTokenId].rentEndTimestamp == 0
        ) {
            trademarkData[startTokenId].rentEndTimestamp =
                block.timestamp +
                trademarkData[startTokenId].duration;
            emit RentStart(
                startTokenId,
                trademarkData[startTokenId].duration,
                trademarkData[startTokenId].rentEndTimestamp
            );
        }
    }

    function isApprovedForAll(
        address tokenOwner,
        address operator
    ) public view virtual override(ERC721A, IERC721A) returns (bool) {
        return
            super.isApprovedForAll(tokenOwner, operator) ||
            msg.sender == owner();
    }

    function transferWithoutRentStart(
        address from,
        address to,
        uint256 tokenId
    ) external onlyOwner {
        require(trademarkData[tokenId].rentEndTimestamp == 0, "NFT is in rent");
        _transfer(from, to, tokenId);
    }

    // Other
    function setRoyalties(
        uint256 tokenId,
        address royalties,
        uint256 royaltyBps
    ) external onlyOwner {
        trademarkData[tokenId].royaltyReceiver = royalties;
        trademarkData[tokenId].royaltyBps = royaltyBps;
    }

    function setRoyaltiesRange(
        uint256 startId,
        uint256 endId,
        address royalties,
        uint256 royaltyBps
    ) external onlyOwner {
        for (uint256 i = startId; i <= endId; i++) {
            trademarkData[i].royaltyReceiver = royalties;
            trademarkData[i].royaltyBps = royaltyBps;
        }
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address, uint256 royaltyAmount) {
        royaltyAmount =
            (_salePrice * trademarkData[_tokenId].royaltyBps) /
            10000;
        return (trademarkData[_tokenId].royaltyReceiver, royaltyAmount);
    }
}

