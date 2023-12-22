// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Ownable.sol";
import "./Ownable.sol";
import "./ERC721.sol";
import "./Counters.sol";
import "./SafeMath.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Enumerable.sol";
import "./IERC20.sol";

contract BXDNFT is ERC721, Ownable, ERC721Enumerable, ERC721URIStorage {
    using Strings for uint256;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    string public constant baseExtension = ".json";
    string public baseTokenURI;

    uint256 public maxSupply;
    uint256 public cost;

    address public payToken;
    address public receiver;
    uint256 public gen;

    mapping(uint256 => address) private _minters;

    event Minted(address indexed minter, uint256 indexed tokenId);

    constructor(address tokenAddress) ERC721("BXDNFT", "BXDNFT") {
        payToken = tokenAddress;
        cost = 250 * 10 ** 6; // 250 tokens
        receiver = msg.sender;
        maxSupply = 160;
        gen = 0;
    }

    function setReceiver(address _receiver) public onlyOwner {
        require(_receiver != address(0), "Invalid address!");
        receiver = _receiver;
    }

    function upgradeToGen1() public onlyOwner {
        require(gen == 0, "Already upgraded!");
        gen = 1;
        maxSupply = 500;
    }

    function setPayToken(address _payToken) public onlyOwner {
        payToken = _payToken;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setCost(uint256 _newCost) public onlyOwner {
        cost = _newCost;
    }

    function getAllMinters() public view returns (address[] memory) {
        address[] memory minters = new address[](maxSupply);
        for (uint256 i = 0; i < maxSupply; i++) {
            minters[i] = _minters[i];
        }
        return minters;
    }

    function walletOfOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        virtual
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    function mintNFTs(uint256 _count) public {
        require(_count > 0, "Must mint at least one NFT!");
        uint totalMinted = _tokenIds.current();

        require(totalMinted.add(_count) <= maxSupply, "Not enough NFTs left!");

        // transfer tokens from sender to contract
        IERC20(payToken).transferFrom(msg.sender, receiver, cost.mul(_count));

        for (uint256 i = 0; i < _count; i++) {
            uint newTokenID = _tokenIds.current();
            _safeMint(msg.sender, newTokenID);
            _minters[newTokenID] = msg.sender;
            _tokenIds.increment();
            emit Minted(msg.sender, newTokenID);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

