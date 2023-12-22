// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Ownable.sol";
import "./Counters.sol";
import "./Pausable.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./EnumerableSet.sol";

contract ERC721Template is Ownable, Pausable, ERC721Enumerable {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    Counters.Counter public tokenIdTracker;
    string public baseUrl;

    struct NftInfo {
        uint256 tokenId;
        string tokenUri;
    }

    event Mint(uint256 indexed tokenId, address indexed to);
    event MintBatch(uint256[] tokenIds, address indexed to);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseUrl
    ) ERC721(_name, _symbol) {
        baseUrl = _baseUrl;
    }

    function setBaseUrl(string memory _baseUrl) public onlyOwner {
        baseUrl = _baseUrl;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address _to) external onlyOwner returns (uint256) {
        tokenIdTracker.increment();
        uint256 tokenId = tokenIdTracker.current();
        _mint(_to, tokenId);
        emit Mint(tokenId, _to);
        return tokenId;
    }

    function mintBatch(
        address _to,
        uint256 _qty
    ) external onlyOwner returns (uint256[] memory tokenIds) {
        require(_qty > 0, "Qty cannot be 0");
        tokenIds = new uint256[](_qty);
        for (uint256 i = 0; i < _qty; i++) {
            tokenIdTracker.increment();
            uint256 tokenId = tokenIdTracker.current();
            _mint(_to, tokenId);
            tokenIds[i] = tokenId;
        }
        emit MintBatch(tokenIds, _to);
        return tokenIds;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return (
            string(
                abi.encodePacked(
                    baseUrl,
                    "/",
                    Strings.toHexString(uint160(address(this)), 20),
                    "/",
                    Strings.toString(_tokenId)
                )
            )
        );
    }

    function tokenIdsOfOwner(
        address _owner
    ) external view returns (uint256[] memory tokenIds) {
        uint256 balance = balanceOf(_owner);
        tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function viewPageTokenIdsOfOwner(
        address _owner,
        uint256 _pageIndex,
        uint256 _pageSize
    ) external view returns (uint256[] memory data, uint256 total) {
        total = balanceOf(_owner);
        if (_pageIndex < 1) {
            _pageIndex = 1;
        }
        uint256 startIndex = (_pageIndex - 1) * _pageSize;
        if (startIndex >= total) {
            return (new uint256[](0), total);
        }

        uint256 endIndex = _pageIndex * _pageSize > total
            ? total
            : _pageIndex * _pageSize;
        data = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            data[i - startIndex] = tokenOfOwnerByIndex(_owner, i);
        }
        return (data, total);
    }

    function viewPageNftInfosOfOwner(
        address _owner,
        uint256 _pageIndex,
        uint256 _pageSize
    ) external view returns (NftInfo[] memory data, uint256 total) {
        total = balanceOf(_owner);
        if (_pageIndex < 1) {
            _pageIndex = 1;
        }
        uint256 startIndex = (_pageIndex - 1) * _pageSize;
        if (startIndex >= total) {
            return (new NftInfo[](0), total);
        }

        uint256 endIndex = _pageIndex * _pageSize > total
            ? total
            : _pageIndex * _pageSize;
        data = new NftInfo[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            data[i - startIndex] = NftInfo({
                tokenId: tokenOfOwnerByIndex(_owner, i),
                tokenUri: tokenURI(tokenOfOwnerByIndex(_owner, i))
            });
        }
        return (data, total);
    }
}

