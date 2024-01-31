// SPDX-License-Identifier: MIT

/**
__________                               __  .__                         
\______   \_______  ____   _____   _____/  |_|  |__   ____  __ __  ______
 |     ___/\_  __ \/  _ \ /     \_/ __ \   __\  |  \_/ __ \|  |  \/  ___/
 |    |     |  | \(  <_> )  Y Y  \  ___/|  | |   Y  \  ___/|  |  /\___ \ 
 |____|     |__|   \____/|__|_|  /\___  >__| |___|  /\___  >____//____  >
                               \/     \/          \/     \/           \/ 

 @powered by: amadeus-nft.io
*/

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./Strings.sol";

contract Prometheus is Ownable, ERC721A, ReentrancyGuard {
    constructor(
    ) ERC721A("Prometheus", "WPL", 10, 5000) {}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    // For marketing etc.
    function reserveMintBatch(uint256[] calldata quantities, address[] calldata tos) external onlyOwner {
        for(uint256 j = 0; j < quantities.length; j++){
            require(
                totalSupply() + quantities[j] <= collectionSize,
                "Too many already minted before dev mint."
                );
            uint256 numChunks = quantities[j] / maxBatchSize;
            for (uint256 i = 0; i < numChunks; i++) {
                _safeMint(tos[j], maxBatchSize);
            }
            if (quantities[j] % maxBatchSize != 0){
                _safeMint(tos[j], quantities[j] % maxBatchSize);
            }
        }
    }

    // metadata URI
    string private _baseTokenURI;

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function withdrawMoney() external onlyOwner nonReentrant {
        address amadeusAddress = address(0x718a7438297Ac14382F25802bb18422A4DadD31b);
        uint256 royaltyForAmadeus = address(this).balance / 100 * 10;
        uint256 remain = address(this).balance - royaltyForAmadeus;
        (bool success, ) = amadeusAddress.call{value: royaltyForAmadeus}("");
        require(success, "Transfer failed.");
        (success, ) = msg.sender.call{value: remain}("");
        require(success, "Transfer failed.");
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
    external
    view
    returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }
    //public sale
    bool public publicSaleStatus = false;
    uint256 public publicPrice = 0.000000 ether;
    uint256 public amountForPublicSale = 5000;
    // per mint public sale limitation
    uint256 public immutable publicSalePerMint = 10;

    function publicSaleMint(uint256 quantity) external payable callerIsUser{
        require(
        publicSaleStatus,
        "not begun"
        );
        require(
        totalSupply() + quantity <= collectionSize,
        "reached max supply"
        );
        require(
        amountForPublicSale >= quantity,
        "reached max amount"
        );

        require(
        quantity <= publicSalePerMint,
        "reached max amount per mint"
        );

        _safeMint(msg.sender, quantity);
        amountForPublicSale -= quantity;
        refundIfOver(uint256(publicPrice) * quantity);
    }

    function setPublicSaleStatus(bool status) external onlyOwner {
        publicSaleStatus = status;
    }
}
