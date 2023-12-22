// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract ExplorersEdition is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    uint256 public constant NORMAL_MXA_SUPPY = 800;
    uint256 public constant SPECIAL_MXA_SUPPY = 99;

    uint256 public stage = 0;

    uint256 public mintPrice;

    uint256[9] public seriesSaleCounts;

    mapping(address => bool) public whiteList;

    mapping(uint256 => bool) public tokenMinted;

    bool public specialHidden = true;

    uint256 public sellingTime;

    Counters.Counter private _tokenIdCounter;

    string private _tokenBaseURI;

    mapping(uint256 => uint256) private _tokenSeries;
    mapping(uint256 => uint256) private _tokenSeriesIndex;

    mapping(address => bool) private _normalMinted;

    // mapping(address => bool) private _specialMinted;

    string private _specialHiddenURI;

    constructor() ERC721("Explorers Edition", "EXPLORERS") {}

    function setSellingTime(uint256 time) external onlyOwner {
        sellingTime = time;
    }

    function setStage(uint256 newStage) external onlyOwner {
        stage = newStage;
    }

    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        mintPrice = newMintPrice;
    }

    function setSpecialHidden(bool hidden) external onlyOwner {
        specialHidden = hidden;
    }

    function setSpecialHiddenURI(string memory uri) external onlyOwner {
        _specialHiddenURI = uri;
    }

    function addWhiteLists(address[] memory users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            whiteList[users[i]] = true;
        }
    }

    function addWhiteList(address user) external onlyOwner {
        whiteList[user] = true;
    }

    function removeWhiteList(address user) external onlyOwner {
        whiteList[user] = false;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _tokenBaseURI = baseURI;
    }

    function withdraw(address recipient) external onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }

    function ownerMint(address recipient, uint256 seriesIndex, uint256 mintCount) external onlyOwner {
        require(seriesIndex >= 0 && seriesIndex <= 8, "series id error");
        uint256 maxSuppy = seriesIndex < 8 ? 100 : SPECIAL_MXA_SUPPY;
        require(seriesSaleCounts[seriesIndex] + mintCount <= maxSuppy, "not so much");

        for (uint256 i = 0; i < mintCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(recipient, tokenId);

            _tokenSeries[tokenId] = seriesIndex;
            _tokenSeriesIndex[tokenId] = seriesSaleCounts[seriesIndex];
            seriesSaleCounts[seriesIndex] += 1;
        }
    }

    function canMintSpecial(address account) public view returns (bool) {
        if (stage != 3) return false;
        // if (_specialMinted[account]) return false;
        if (seriesSaleCounts[8] >= SPECIAL_MXA_SUPPY) return false;

        uint256 balance = balanceOf(account);
        bool[] memory hasTokenSeries = new bool[](8);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenID = tokenOfOwnerByIndex(account, i);
            if (tokenMinted[tokenID]) {
                continue;
            }
            uint256 seriesIndex = _tokenSeries[tokenID];
            if (seriesIndex == 8) {
                continue;
            }
            hasTokenSeries[seriesIndex] = true;
        }

        for (uint256 i = 0; i < hasTokenSeries.length; i++) {
            if (!hasTokenSeries[i]) {
                return false;
            }
        }

        return true;
    }

    function mint() external payable {
        require((stage == 1 && whiteList[msg.sender]) || stage == 2, "Not on sale");

        require(!_normalMinted[msg.sender], "Only one mint");

        require(mintPrice <= msg.value, "Ethereum sent is not sufficient.");

        uint256 length = 0;
        uint256 saledCount = 0;
        for (uint256 i = 0; i < seriesSaleCounts.length - 1; i++) {
            if (seriesSaleCounts[i] < 100) {
                length++;
            }
            saledCount += seriesSaleCounts[i];
        }

        require(saledCount < NORMAL_MXA_SUPPY, "Only 800 are mintable!");

        uint256 tokenId = _tokenIdCounter.current();

        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);

        uint256[] memory seriesIndexes = new uint256[](length);
        uint256 index = 0;
        for (uint256 i = 0; i < seriesSaleCounts.length - 1; i++) {
            if (seriesSaleCounts[i] < 100) {
                seriesIndexes[index] = i;
                index++;
            }
        }

        uint256 seriesIndex = seriesIndexes[
            uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % length
        ];
        _tokenSeries[tokenId] = seriesIndex;
        _tokenSeriesIndex[tokenId] = seriesSaleCounts[seriesIndex];
        seriesSaleCounts[seriesIndex] += 1;

        _normalMinted[msg.sender] = true;
    }

    function specialMint() external payable {
        require(mintPrice <= msg.value, "Ethereum sent is not sufficient.");
        require(stage == 3, "Not on sale");
        require(seriesSaleCounts[8] < SPECIAL_MXA_SUPPY, "Only 99 are mintable!");

        uint256 balance = balanceOf(msg.sender);
        bool[] memory hasTokenSeries = new bool[](8);
        uint256[] memory tokenMint = new uint256[](8);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenID = tokenOfOwnerByIndex(msg.sender, i);
            if (tokenMinted[tokenID]) {
                continue;
            }
            uint256 seriesIndex = _tokenSeries[tokenID];
            if (seriesIndex == 8) {
                continue;
            }
            hasTokenSeries[seriesIndex] = true;
            tokenMint[seriesIndex] = tokenID;
        }

        for (uint256 i = 0; i < hasTokenSeries.length; i++) {
            require(hasTokenSeries[i], "Can not mint.");
        }

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);

        _tokenSeries[tokenId] = 8;
        _tokenSeriesIndex[tokenId] = seriesSaleCounts[8];
        seriesSaleCounts[8] += 1;

        // _specialMinted[msg.sender] = true;
        for (uint256 i = 0; i < tokenMint.length; i++) {
            tokenMinted[tokenMint[i]] = true;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        if (_tokenSeries[tokenId] == 8 && specialHidden) {
            return _specialHiddenURI;
        }

        string memory baseURI = _baseURI();

        if (bytes(baseURI).length <= 0) {
            return "";
        }

        uint256 uriID = _tokenSeries[tokenId] * 100 + _tokenSeriesIndex[tokenId];

        return string(abi.encodePacked(baseURI, uriID.toString()));
    }
}

