// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
//import "@openzeppelin/contracts@4.8.0/utils/Counters.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract CombatBaze is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {

    //using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

   // Counters.Counter private _tokenIdCounter;

    struct TokenInfo {
        IERC20 paytoken;
    }

    struct TokenRarity {
        uint256 id;
        uint256 costEth;
        uint256 costToken0;
        uint256 rarity;
        uint256 isPurchased;
    }

    IERC20 paytoken;
    TokenInfo[] public AllowedCrypto;
    TokenRarity[] public TokenRarityInfo;

    uint256 public maxSupply; //Maximum amount token
    bool public isMintEnabled; //default : false
    mapping(address=>uint256) public MintedWallets;
    mapping(uint256=>TokenRarity) public TokenData;
    string public baseURI;


    constructor() ERC721("CombatBaze", "COMB") {
        maxSupply = 0;
    }

    function addCurrency(IERC20 _paytoken) external onlyOwner {
        AllowedCrypto.push(
            TokenInfo({
                paytoken: _paytoken
            })
        );
    }

    function addTokens(uint256 _tokenId, uint256 _costEth, uint256 _costToken0, uint256 _rarity) external onlyOwner {

        TokenRarity memory newRequest = TokenRarity({
                id: _tokenId,
                costEth: _costEth,
                costToken0: _costToken0,
                rarity: _rarity,
                isPurchased: 0
            });

        TokenData[_tokenId] = newRequest;
        
    }

    function updateTokenPrice(uint256 _tokenId, uint256 _costEth, uint256 _costToken0 ) external onlyOwner {
        TokenData[_tokenId].costEth = _costEth;
        TokenData[_tokenId].costToken0 = _costToken0;
    }

    function updateTokenPurchased(uint256 _tokenId) internal {
        TokenData[_tokenId].isPurchased = 1;
    }

    function buyMembershipErc(uint256 _tokenId, uint256 _pid) external payable {
        TokenInfo storage tokens = AllowedCrypto[_pid];
        TokenRarity storage token_data = TokenData[_tokenId];
        paytoken = tokens.paytoken;
        require(msg.value >= token_data.costToken0, "Price Error");
        paytoken.transferFrom(msg.sender, address(this), msg.value);
        mintMembership(_tokenId,token_data.rarity,token_data.isPurchased);
    }

    function buyMembershipEth(uint256 _tokenId) external payable {
        TokenRarity storage token_data = TokenData[_tokenId];
        require(msg.value >= token_data.costEth, "Price Error");
        mintMembership(_tokenId,token_data.rarity,token_data.isPurchased);
    }

    function mintMembership(uint256 _tokenId, uint256 rarityItem, uint256 purchasedStatus) internal {
        require(isMintEnabled, "Not For Sale");
        require(totalSupply() < maxSupply, "Sold Out");
        require(purchasedStatus == 0, "Token already sold");
        require(rarityItem != 3, "Not For Sale Diamond");
        updateTokenPurchased(_tokenId);
        _safeMint(msg.sender, _tokenId);
    }

    function ownerBuy(uint256 _tokenId) external onlyOwner {
        updateTokenPurchased(_tokenId);
        _safeMint(msg.sender, _tokenId);
    }

    function setMintEnabled(bool isMintEnabled_) external onlyOwner {
        isMintEnabled = isMintEnabled_;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    function setMaxSupply(uint256 maxSupply_) external onlyOwner{
        maxSupply = maxSupply_;
    }

    function withdraw() public onlyOwner {
        require(address(this).balance > 0, "Balance is 0");
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawToken(uint256 _pid) external onlyOwner {
        TokenInfo storage tokens = AllowedCrypto[_pid];
        paytoken = tokens.paytoken;
        paytoken.transfer(msg.sender,paytoken.balanceOf(address(this)));
    }

  // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}



