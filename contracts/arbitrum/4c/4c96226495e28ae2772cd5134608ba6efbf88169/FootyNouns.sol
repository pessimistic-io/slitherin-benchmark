// SPDX-License-Identifier: GPL-3.0

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import {Strings} from "./Strings.sol";

import {IFootySeeder} from "./IFootySeeder.sol";
import {IFootyDescriptor} from "./IFootyDescriptor.sol";

pragma solidity ^0.8.0;

contract FootyNouns is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;
    event Mint(address indexed owner, uint256 indexed tokenId, uint256 price);
    using Counters for Counters.Counter;
    Counters.Counter _tokenIds;
    Counters.Counter _mintedForFree;

    uint256 public mintOnePrice = 30000000000000000; //0.03 ETH for one
    uint256 public mintThreePrice = 25000000000000000; //0.025 ETH per unit when more than 3 for three
    uint256 public mintFivePrice = 20000000000000000; //0.02 per unit when more than 5 ETH for five

    uint256 public MAX_FREE_SUPPLY = 500;
    uint256 public MAX_SUPPLY = 5000;

    bool public isLive = true;

    bool public renderOnChain = false;

    mapping(address => bool) public mintedFree;

    mapping(uint256 => IFootySeeder.FootySeed) public seeds;

    IFootyDescriptor public descriptor;
    IFootySeeder public seeder;

    constructor(IFootyDescriptor _descriptor, IFootySeeder _seeder)
        ERC721("FootyNouns", "FN")
    {
        descriptor = _descriptor;
        seeder = _seeder;
    }

    function toggleLive() external onlyOwner {
        isLive = !isLive;
    }

    function toggleChainRender() external onlyOwner {
        renderOnChain = !renderOnChain;
    }

    function _internalMint(address _address) internal returns (uint256) {
        require(isLive == true, "Minting is not live");
        // minting logic
        uint256 current = _tokenIds.current();
        require(current < MAX_SUPPLY, "Max supply has been reached");

        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();

        IFootySeeder.FootySeed memory seed = seeds[tokenId] = seeder
            .generateFootySeed(tokenId, descriptor);

        _safeMint(_address, tokenId);
        emit Mint(_address, tokenId, msg.value);
        return tokenId;
    }

    // Allow the owner to claim a nft
    function ownerClaim(uint256 amount, address _address)
        public
        nonReentrant
        onlyOwner
    {
        for (uint256 i = 0; i < amount; i++) {
            _internalMint(_address);
        }
    }

    function mintFree() public nonReentrant {
        require(mintedFree[msg.sender] != true, "Already minted for free");
        uint256 current = _mintedForFree.current();
        require(current < MAX_FREE_SUPPLY, "All free have been minted");
        _internalMint(_msgSender());
        mintedFree[msg.sender] = true;
        _mintedForFree.increment();
    }

    function mint() public payable nonReentrant {
        require(mintOnePrice <= msg.value, "Ether value sent is not correct");
        _internalMint(_msgSender());
    }

    // mint many, price fluctuates with the amount
    function mintMany(uint256 amount) public payable nonReentrant {
        uint256 totalPrice = mintOnePrice * amount;

        if (amount >= 4) {
            totalPrice = mintFivePrice * amount;
        } else if (amount >= 3) {
            totalPrice = mintThreePrice * amount;
        }

        require(totalPrice <= msg.value, "Ether value sent is not correct");
        require(amount <= 5, "Maximum 5 mints");

        for (uint256 i = 0; i < amount; i++) {
            _internalMint(_msgSender());
        }
    }

    string private baseURI = "https://footynouns.wtf/api/token/";

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    string private _contractURI = "https://footynouns.wtf/api/metadata/";

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory newContractURI) external onlyOwner {
        _contractURI = newContractURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");

        if (renderOnChain) {
            return descriptor.tokenURI(tokenId, seeds[tokenId]);
        } else {
            return string(abi.encodePacked(_baseURI(), tokenId.toString()));
        }
    }

    // owner functions
    function ownerWithdraw() external onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }

    function setDescriptor(IFootyDescriptor _descriptor) external onlyOwner {
        descriptor = _descriptor;
    }

    function setSeeder(IFootySeeder _seeder) external onlyOwner {
        seeder = _seeder;
    }

    function setMintOnePrice(uint256 newMintOnePrice) external onlyOwner {
        mintOnePrice = newMintOnePrice;
    }

    function setMintThreePrice(uint256 newMintThreePrice) external onlyOwner {
        mintThreePrice = newMintThreePrice;
    }

    function setMintFivePrice(uint256 newMintFivePrice) external onlyOwner {
        mintFivePrice = newMintFivePrice;
    }

    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        MAX_SUPPLY = newMaxSupply;
    }

    function setMaxFreeSupply(uint256 newMaxFreeSupply) external onlyOwner {
        MAX_FREE_SUPPLY = newMaxFreeSupply;
    }
}

