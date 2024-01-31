// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";

interface IOTMintBonus {
    function mintBonus(address to, uint256 numTokens) external;
}

contract YokozePass is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 private constant MAX_SUPPLY = 350;
    uint256 private constant MAX_PER_MINT = 5;

    // ERC721Metadata
    string private baseURI;

    // Sale
    uint256 public price = 0.0031 ether;
    bool public isSaleActive;

    // $OPENTOWN
    IOTMintBonus public otNFTBonusIssuerContract;

    // Wallets
    address payable public yokozeWallet;
    address payable public devWallet;

    constructor(
        string memory initBaseURI,
        address otNFTBonusIssuerAddr
    ) ERC721("Yokoze Pass", "YP") {
        require(otNFTBonusIssuerAddr != address(0), "Invalid address");
        otNFTBonusIssuerContract = IOTMintBonus(otNFTBonusIssuerAddr);
        baseURI = initBaseURI;
    }

    // ERC721Metadata
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
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
                        ".json"
                    )
                )
                : "";
    }

    // Sale
    function setPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
    }

    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;
    }

    function mint(address to, uint256 mintAmount) external payable {
        require(isSaleActive, "Sale is not active");
        require(to != address(0), "Invalid address");
        require(mintAmount > 0, "Need at least 1 token");
        require(mintAmount <= MAX_PER_MINT, "5 tokens per call max");
        require(msg.value >= price * mintAmount, "Incorrect Ether amount");

        uint256 supply = totalSupply();
        require(supply + mintAmount <= MAX_SUPPLY, "Exceeds maximum supply");

        for (uint256 i = 1; i <= mintAmount; i++) {
            _safeMint(to, supply + i);
        }
        otNFTBonusIssuerContract.mintBonus(to, mintAmount);
    }

    // $OPENTOWN
    function setOTNFTBonusIssuerContract(address addr) external onlyOwner {
        require(addr != address(0), "Invalid address");
        otNFTBonusIssuerContract = IOTMintBonus(addr);
    }

    // Wallets
    function setYokozeWallet(address payable addr) external onlyOwner {
        require(addr != address(0), "Invalid address");
        yokozeWallet = addr;
    }

    function setDevWallet(address payable addr) external onlyOwner {
        require(addr != address(0), "Invalid address");
        devWallet = addr;
    }

    function withdraw() external onlyOwner {
        require(yokozeWallet != address(0), "Yokoze address not set");
        require(devWallet != address(0), "Dev address not set");

        uint256 yokozePart = (address(this).balance * 80) / 100;

        // Send 80% of funds to Yokoze
        (bool yokozeSuccess, ) = yokozeWallet.call{value: yokozePart}("");
        require(yokozeSuccess, "Failed to send Ether to Yokoze");

        // Send the other 20% to developer
        (bool devSuccess, ) = devWallet.call{value: address(this).balance}("");
        require(devSuccess, "Failed to send Ether to dev");
    }

    // Utilities
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }
}

