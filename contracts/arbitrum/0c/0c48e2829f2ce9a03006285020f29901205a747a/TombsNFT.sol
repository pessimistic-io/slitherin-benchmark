// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import {MerkleProof} from "./MerkleProof.sol";

import "./ERC721Pausable.sol";

contract TombsNFT is ERC721Enumerable, Ownable, ERC721Burnable, ERC721Pausable {
    using SafeMath for uint256;

    bytes32 public mintWhitelistMerkleRoot;
    bytes32 public freeMintMerkleRoot;
    uint64 public goLiveDate;
    uint64 public preSalePeriod;
    address public multiSigTreasuryAddress;

    mapping(address => bool) public freeMintBlackList;

    // Token Price
    uint256 public PRICE_WHITELIST = 17 * 10 ** 15; // 30 ARB Per Tombs
    uint256 public PRICE_PUBLIC = 22 * 10 ** 15; // 40 ARB Per Tombs

    uint256 public constant MAX_SUPPLY = 5000; // 5000 Crypto Tombs in CrowdSale
    uint256 private constant MAX_AMOUNT_PRIVATE = 1000; // 1000 Crypto Tombs in PreSale

    uint256 public constant MAX_MINT_PRESALE = 5; // Upper Limit is 2 in PreSale
    uint256 public PHASE_MINT_LIMIT = 1500;

    string private baseTokenURI;

    uint256[] private _occupiedList;

    mapping(uint256 => bool) private _isOccupiedId;

    event CreateTombs(address to, uint256 indexed id);

    constructor(
        string memory baseURI,
        bytes32 _mintWhitelistMerkleRoot,
        bytes32 _freeMintMerkleRoot,
        uint64 _goLiveDate,
        uint64 _preSalePeriod
    ) ERC721("Tombs", "TMB") {
        setBaseURI(baseURI);
        mintWhitelistMerkleRoot = _mintWhitelistMerkleRoot;
        freeMintMerkleRoot = _freeMintMerkleRoot;
        goLiveDate = _goLiveDate;
        preSalePeriod = _preSalePeriod;
    }

    function mint(address payable _to, uint256 amount, bytes32[] calldata merkleProof) public payable {
        uint256 total = _totalSupply();

        require(block.timestamp >= goLiveDate, "MINT: Invalid timestamp");
        require(total + amount <= PHASE_MINT_LIMIT, "MINT: Current count exceeds maximum element count.");
        require(total <= PHASE_MINT_LIMIT, "MINT: Please go to the Opensea to buy Tombs.");

        bytes32 node = keccak256(abi.encodePacked(msg.sender));

        if (block.timestamp <= goLiveDate + preSalePeriod) {
            if (MerkleProof.verify(merkleProof, mintWhitelistMerkleRoot, node)) {
                require(amount + balanceOf(_to) <= MAX_MINT_PRESALE, "Invalid amount for a whitelist");
                require(msg.value >= amount * PRICE_WHITELIST, "Whitelist Insufficient balance");
                for (uint256 i = 0; i < amount; i++) {
                    _mintAnElement(_to);
                }
            } else if (MerkleProof.verify(merkleProof, freeMintMerkleRoot, node)) {
                require(freeMintBlackList[msg.sender] == false, "You already mint freely");
                _mintAnElement(_to);
                freeMintBlackList[msg.sender] = true;
            }
        } else {
            require(msg.value >= amount * PRICE_PUBLIC, "Public sale Insufficient balance");
            for (uint256 i = 0; i < amount; i++) {
                _mintAnElement(_to);
            }
        }
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function setMultiSigTreasury(address _multiSig) public onlyOwner {
        require(_multiSig != address(0x0), "Invalid Addr");
        multiSigTreasuryAddress = _multiSig;
    }

    function raised() public view returns (uint256) {
        return address(this).balance;
    }

    function getTokenIdsOfWallet(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function withdrawAll() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "WITHDRAW: No balance in contract");
        require(multiSigTreasuryAddress != address(0x0), "Invalid Addr");
        (bool success, ) = multiSigTreasuryAddress.call{value: balance}("");
        require(success, "WITHDRAW: Transfer failed.");
    }

    function setLiveDate(uint64 liveDate) public onlyOwner {
        goLiveDate = liveDate;
    }

    function setPresalePeriod(uint64 period) public onlyOwner {
        preSalePeriod = period;
    }

    function setWhiteList(bytes32 merkleRoot) public onlyOwner {
        mintWhitelistMerkleRoot = merkleRoot;
    }

    function setFreeMintList(bytes32 merkleRoot) public onlyOwner {
        freeMintMerkleRoot = merkleRoot;
    }

    function setMintPrice(uint256 priceWhiteList, uint256 pricePublic) public onlyOwner {
        PRICE_WHITELIST = priceWhiteList;
        PRICE_PUBLIC = pricePublic;
    }

    function setPhaseMintLimit(uint256 limit) public onlyOwner {
        require(limit <= MAX_SUPPLY, "Limit is exceed max supply");
        PHASE_MINT_LIMIT = limit;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _mintAnElement(address payable _to) private {
        require(_totalSupply() < MAX_SUPPLY, "CoolNFTs are sold out!");

        uint tokenId = _generateTokenId();

        _safeMint(_to, tokenId);

        _isOccupiedId[tokenId] = true;
        _occupiedList.push(tokenId);

        emit CreateTombs(_to, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function _totalSupply() internal view returns (uint) {
        return _occupiedList.length;
    }

    function _createRandomNumber(uint256 seed) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, seed))) % MAX_SUPPLY;
    }

    function _generateTokenId() private view returns (uint256) {
        uint256 tokenId;
        for (uint256 i = 0; ; i++) {
            tokenId = _createRandomNumber(i);
            if (!_isOccupiedId[tokenId]) break;
        }
        return tokenId;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}

