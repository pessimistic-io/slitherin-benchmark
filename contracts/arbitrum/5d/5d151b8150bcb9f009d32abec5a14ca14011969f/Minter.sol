// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./ERC721URIStorage.sol";

interface PulsarBalanceVerifier {
    function isEveryTokenBalanceCorrect(
        address[] memory _tokens,
        uint256[] memory _tokenBalances,
        address _walletAddress
    ) external view;
}

interface PulsarClassifier {
    function classifyWallet(
        address wallet,
        address[] memory _tokens,
        uint256[] memory _tokenBalances,
        uint256[] memory _tokenPrices,
        uint8[] memory _tokenDecimals,
        uint8[] memory _priceDecimals,
        uint256[] memory _defiContractUSDBalances,
        uint256[] memory _nftUSDBalances
    ) external view returns (uint8);
}

contract Minter is ERC721URIStorage {
    PulsarBalanceVerifier internal _pulsarBalanceVerifier;
    PulsarClassifier internal _pulsarClassifier;

    uint256 public tokenCounter;
    string[] private _badgeURIs;

    enum BadgeType {
        POOR,
        LOW_CAP_DEGEN,
        NFT_DEGEN,
        DEFI_DEGEN,
        BOLD,
        CONSERVATIVE
    }

    mapping(uint256 => BadgeType) public tokenIdToBadgeType;
    mapping(uint256 => address) public tokenIdtoWallet;
    mapping(uint256 => string) private _tokenURIs;

    event TypeAssigned(uint256 indexed tokenId, BadgeType badgeType);
    event BalanceVerified();
    event AttributedBadge(BadgeType badgeType, string tokenURI, address sender);

    // On contract instantiation _badgeURIsList must be sorted matching the order of the BadgeType enum.
    constructor(
        address _pulsarBalanceVerifierAddr,
        address _pulsarClassifierAddr,
        string[] memory _badgeURIsList
    ) ERC721("PulsarBadges", "PULS") {
        require(
            _badgeURIsList.length == 6,
            "Number of badge URIs provided differs from the length of BadgeType enum"
        );
        tokenCounter = 0;
        _pulsarBalanceVerifier = PulsarBalanceVerifier(
            _pulsarBalanceVerifierAddr
        );
        _pulsarClassifier = PulsarClassifier(_pulsarClassifierAddr);
        _badgeURIs = _badgeURIsList;
    }

    // tokens - Array containing from 0 to 100 token addresses (Contract tokens only!)
    // _tokenBalances - unparsed | Ex: 1000000 for 1 USDC
    // _tokenPrices [USD] - unpsarsed | Ex: 1800000000000000000000 for ETH at 1800 usd price
    // _priceDecimals - Ex: 18 for the example above
    // _tokenDecimals - same as definded at ERC20 contract / 18 for native
    // _defiContractUSDBalances [USD] - parsed | Ex: 1500 for 1500 usd balance
    // _nftUSDBalances [USD] - parsed | Ex: 1500 for 1500 usd balance
    function createBadge(
        address[] memory _tokens,
        uint256[] memory _tokenBalances,
        uint256[] memory _tokenPrices,
        uint8[] memory _tokenDecimals,
        uint8[] memory _priceDecimals,
        uint256[] memory _defiContractUSDBalances,
        uint256[] memory _nftUSDBalances
    ) public {
        require(_tokens.length <= 100, "Max token length exceded");
        require(
            _tokens.length == _tokenBalances.length,
            "Tokens, token related inputs must have the same length"
        );
        require(
            _tokens.length == _tokenPrices.length,
            "Tokens, token related inputs must have the same length"
        );
        require(
            _tokens.length == _tokenDecimals.length,
            "Tokens, token related inputs must have the same length"
        );
        require(
            _tokens.length == _priceDecimals.length,
            "Tokens, token related inputs must have the same length"
        );
        _pulsarBalanceVerifier.isEveryTokenBalanceCorrect(
            _tokens,
            _tokenBalances,
            msg.sender
        );
        emit BalanceVerified();
        uint8 badgeTypeId = _pulsarClassifier.classifyWallet(
            msg.sender,
            _tokens,
            _tokenBalances,
            _tokenPrices,
            _tokenDecimals,
            _priceDecimals,
            _defiContractUSDBalances,
            _nftUSDBalances
        );
        uint256 newTokenId = tokenCounter;
        BadgeType badgeType = BadgeType(badgeTypeId);
        tokenIdToBadgeType[newTokenId] = badgeType;
        emit TypeAssigned(newTokenId, badgeType);
        tokenIdtoWallet[newTokenId] = msg.sender;
        address owner = tokenIdtoWallet[newTokenId];
        _safeMint(owner, newTokenId);
        string memory tokenURI = _badgeURIs[badgeTypeId];
        _setTokenURI(newTokenId, tokenURI);
        tokenCounter = tokenCounter + 1;
        emit AttributedBadge(badgeType, tokenURI, msg.sender);
    }
}

