// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./IERC20.sol";

contract UtopiaNFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    mapping(uint256 => string) private _tokenURIs;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public freeGroup;

    IERC20 public arbToken; // ARB Token address
    address public treasuryWallet;

    uint256 public standardPrice = 350 * 10**18;  
    uint256 public whitelistPrice = 250 * 10**18;
    uint256 public constant MAX_SUPPLY = 2222;

    bool public mintingEnabled = false;
    bool public whitelistSaleEnabled = false;
    bool public freeSaleEnabled = false;
    bool public publicSaleEnabled = false;
    

    constructor(address _arbTokenAddress) ERC721("Utopia Portals", "UTPS") {
       arbToken = IERC20(_arbTokenAddress);
       treasuryWallet = msg.sender;
    }

    function addToWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
    }

    function addToWhitelistMulti(address[] memory users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            whitelist[users[i]] = true;
        }
    }

    function removeFromWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
    }

    function addToFreeGroup(address user) external onlyOwner {
        freeGroup[user] = true;
    }

     function addToFreeGroupMulti(address[] memory users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            freeGroup[users[i]] = true;
        }
    }

    function removeFromFreeGroup(address user) external onlyOwner {
        freeGroup[user] = false;
    }

    function mint(address recipient, string memory uri) external {
        require(mintingEnabled, "Minting is currently disabled");

        if(whitelist[msg.sender]){
            require(whitelistSaleEnabled, "Whitelist sale not enabled");
        } else if(freeGroup[msg.sender]) {
            require(freeSaleEnabled, "Free sale not enabled");
        } else {
            require(publicSaleEnabled, "Public sale not enabled");
        }

        uint256 price = getMintPrice(msg.sender);

        uint256 userBalance = arbToken.balanceOf(msg.sender);
        require(userBalance >= price, "Insufficient ARB balance");

        uint256 allowedAmount = arbToken.allowance(msg.sender, address(this));
        require(allowedAmount >= price, "Contract not allowed to spend enough ARB");

        if(price > 0) {
            require(arbToken.transferFrom(msg.sender, treasuryWallet, price), "Token transfer failed");
        }
        
        _mintNFT(recipient, uri);
    }
    
    
    function mintMultiple(address recipient, string[] memory uris) external {
        require(mintingEnabled, "Minting is currently disabled");

        if(whitelist[msg.sender]){
            require(whitelistSaleEnabled, "Whitelist sale not enabled");
        } else if(freeGroup[msg.sender]) {
            require(freeSaleEnabled, "Free sale not enabled");
        } else {
            require(publicSaleEnabled, "Public sale not enabled");
        }

        uint256 numToMint = uris.length;

        uint256 totalPrice = getMintPrice(msg.sender) * numToMint;

        uint256 userBalance = arbToken.balanceOf(msg.sender);
        require(userBalance >= totalPrice, "Insufficient ARB balance");

        uint256 allowedAmount = arbToken.allowance(msg.sender, address(this));
        require(allowedAmount >= totalPrice, "Contract not allowed to spend enough ARB");

        require(arbToken.transferFrom(msg.sender, treasuryWallet, totalPrice), "Token transfer failed");

        for(uint256 i = 0; i < numToMint; i++) {
            _mintNFT(recipient, uris[i]);
        }

    }
    

    function getMintPrice(address user) public view returns (uint256) {
        if (freeGroup[user]) return 0;
        if (whitelist[user]) return whitelistPrice;
        return standardPrice;
    }

    function _mintNFT(address recipient, string memory uri) internal {
        require(_tokenIdCounter.current() < MAX_SUPPLY, "All NFTs have been minted");
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        _safeMint(recipient, newTokenId);
        _setTokenURI(newTokenId, uri);
    }

    function _setTokenURI(uint256 tokenId, string memory uri) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = uri;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }

    function remainingNFTs() external view returns (uint256) {
        return MAX_SUPPLY - _tokenIdCounter.current();
    }

    function enableMinting() external onlyOwner {
        mintingEnabled = true;
    }

    function disableMinting() external onlyOwner {
        mintingEnabled = false;
    }

    function setTreasuryWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "Invalid address");
        treasuryWallet = _newWallet;
    }

    function enableWhitelistSale() external onlyOwner {
        whitelistSaleEnabled = true;
    }

    function disableWhitelistSale() external onlyOwner {
        whitelistSaleEnabled = false;
    }

    function enableFreeSale() external onlyOwner {
        freeSaleEnabled = true;
    }

    function disableFreeSale() external onlyOwner {
        freeSaleEnabled = false;
    }

    function enablePublicSale() external onlyOwner {
        publicSaleEnabled = true;
    }

    function disablePublicSale() external onlyOwner {
        publicSaleEnabled = false;
    }

}

