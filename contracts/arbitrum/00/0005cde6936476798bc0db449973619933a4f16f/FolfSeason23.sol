// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./FolfSeason23NFTStorage.sol";

contract FolfSeason23 is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    FolfSeason23NFTStorage
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;
    event GameCreated(
        address indexed player1,
        address indexed player2,
        uint16[2] score,
        uint256 indexed tokenId,
        address winner,
        string uri
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("FolfSeason23", "FS23");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    modifier onlyOneOfPlayers(uint256 tokenId) {
            require(msg.sender == tokenIdToFolfGameData[tokenId].players[0] || msg.sender == tokenIdToFolfGameData[tokenId].players[1], "Require: sender must be one of the players.");
            _;
    }

    modifier onlyWhenNotAccepted(uint256 tokenId){
        require(!tokenIdToFolfGameData[tokenId].accepted[0] || !tokenIdToFolfGameData[tokenId].accepted[1], "Require: Game Data must not be universally accepted.");
        _;
    }

    function createGame(
        address[2] memory _players,
        uint16[2] memory _score,
        address winner,
        string memory metadataUri,
        address to
    ) public {
        FolfGameData memory gd = FolfGameData(
            _players,
            _score,
            [msg.sender == _players[0], msg.sender == _players[1]],
            winner
        );
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataUri);
        tokenIdToFolfGameData[tokenId] = gd;
        emit GameCreated(
            gd.players[0],
            gd.players[1],
            gd.score,
            tokenId,
            gd.winner,
            metadataUri
        );
    }

    function acceptGameData(uint256 tokenId) public onlyWhenNotAccepted(tokenId) onlyOneOfPlayers(tokenId) {
        FolfGameData storage gd = tokenIdToFolfGameData[tokenId];
        uint256 idx;
        if(msg.sender == gd.players[0]){
            idx = 0;
        } else {
            idx = 1;
        }
        gd.accepted[idx] = true;
    }

    function rejectAndBurnNFT(uint256 tokenId) public onlyWhenNotAccepted(tokenId) onlyOneOfPlayers(tokenId) {
        delete tokenIdToFolfGameData[tokenId];
        _burn(tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        delete tokenIdToFolfGameData[tokenId];
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

