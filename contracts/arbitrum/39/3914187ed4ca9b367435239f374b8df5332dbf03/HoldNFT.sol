// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./ERC721.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Burnable.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract HoldNFT is
    ERC721,
    Pausable,
    Ownable,
    ERC721Burnable,
    ReentrancyGuard,
    ERC721Enumerable,
    ERC721URIStorage
{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _itemIdCounter;

    uint256 public mintFee = 100 ether;
    IERC20 public mintFeeToken;

    address public feeRecipient;
    uint256 totalFee;

    string public baseURI;
    string private _uriSuffix = ".json";

    constructor(
        address owner,
        address _feeRecipient,
        address _mintFeeToken
    ) ERC721("Hold", "HOLD") {
        super._transferOwnership(owner);
        mintFeeToken = IERC20(_mintFeeToken);
        feeRecipient = _feeRecipient;
        baseURI = "https://nft.hold.vip/json/";
    }

    function setMintFee(uint256 _mintFee) public onlyOwner {
        mintFee = _mintFee;
    }

    function setmintFeeToken(address _mintFeeToken) public onlyOwner {
        mintFeeToken = IERC20(_mintFeeToken);
    }

    function setFeeRecipient(address _feeRecipient) public onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function contractURI() public view returns (string memory) {
        return "https://nft.hold.vip/json/nftcollection.json";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMintMany(
        address to,
        uint256 amount,
        uint256[] memory _tokenId
    ) public payable {
        uint256 feeRequire = amount * mintFee;
        require(
            amount == _tokenId.length,
            "Amount and amount of token id not match"
        );
        require(
            mintFeeToken.balanceOf(_msgSender()) >= feeRequire,
            "Insufficient Balance"
        );
        require(
            mintFeeToken.allowance(_msgSender(), address(this)) >= feeRequire,
            "Insufficient Allowance"
        );
        require(
            mintFeeToken.transferFrom(_msgSender(), address(this), feeRequire),
            "transfer failed"
        );
        totalFee += feeRequire;
        uint256 tokenId;
        string memory uri;
        for (uint8 i = 0; i < amount; i++) {
            _tokenIdCounter.increment();
            tokenId = _tokenIdCounter.current();
            uri = string(
                abi.encodePacked(Strings.toString(_tokenId[i]), _uriSuffix)
            );
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uri);
        }
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function withdraw() public nonReentrant onlyOwner {
        mintFeeToken.safeTransfer(feeRecipient, totalFee);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

