
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Counters.sol";
import "./SafeMath.sol";

contract SeedPhraseHint is ERC721, AccessControl {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    event SeedPhraseGuessed(address winner, uint256 prize);
    event SeasonStarted(address winner);
    event MintPriceChanged(uint256 price);

    bytes32 public constant WINNER_ROLE = keccak256("WINNER_ROLE");
    Counters.Counter private _tokenIdCounter;

    // @dev defaults
    uint256 mintPrice = 0.005 ether;
    string baseURI = "https://api.seedphrase.pictures/meta/";

    constructor() ERC721("Seed Phrase Hint", "HINT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // @dev: mint tokenId 0 to deployer
        _safeMint(msg.sender, 0);
        // @dev: mint 10 more to deployer to provide some example HINTs to get things started
        for (uint256 i = 0; i < 10; i++) {
            _tokenIdCounter.increment();
            _safeMint(msg.sender, _tokenIdCounter.current());
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function safeMint(address to) public payable {
        require(msg.value >= mintPrice, "!value");
        _tokenIdCounter.increment();
        _safeMint(to, _tokenIdCounter.current());
    }

    function batchMint(address to, uint256 quantity) public payable {
        require(msg.value >= mintPrice.mul(quantity), "!value");
        for (uint256 i = 0; i < quantity; i++) {
            _tokenIdCounter.increment();
            _safeMint(to, _tokenIdCounter.current());
        }
    }

    function setMintPrice(uint256 _price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPrice = _price;
        emit MintPriceChanged(_price);
    }

    function setBaseURI(string calldata _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _uri;
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function withdraw() external onlyRole(WINNER_ROLE) {
        // @dev: 5% to deployer
        bool sent = payable(ownerOf(0)).send(address(this).balance.mul(5).div(100));
        require(sent, "!send");
        // @dev: 95% to winner
        emit SeedPhraseGuessed(msg.sender, address(this).balance);
        sent = payable(msg.sender).send(address(this).balance);
        require(sent, "!send");
        // @dev revoke WINNER role, so this account cannot withdraw again
        _revokeRole(WINNER_ROLE, msg.sender);
    }

    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        super.grantRole(role, account);
        if (role == WINNER_ROLE) {
            emit SeasonStarted(account);
        }
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}
}
