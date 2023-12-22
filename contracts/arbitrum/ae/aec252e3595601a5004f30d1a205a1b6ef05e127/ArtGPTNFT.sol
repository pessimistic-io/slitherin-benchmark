//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import {ERC20} from "./ERC20.sol";
import "./SafeERC20.sol";
import "./UniversalERC20.sol";

contract ArtGPTNFT is
    ERC721Enumerable,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using Strings for uint256;
    using Counters for Counters.Counter;
    using UniversalERC20 for IERC20;
    struct Config {
        uint256 maxSupply;
        bool mintStarted;
        uint256 price;
        address token;
    }

    Config public config;
    string public baseURI = "";
    mapping(uint256 => string) public prompts;
    mapping(uint256 => address) public orderers;
    Counters.Counter private _publicArts;

    // ------------------------------ ROLE -----------------------
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ------------------------------ EVENT -----------------------
    event Order(address _user, uint256 _token_id, string prompt);
    event Shipped(address _user, uint256 _token_id);

    constructor(
        Config memory _config,
        string memory _baseURI,
        address _minter
    ) ERC721("artGPT", "artGPT") {
        config = _config;
        baseURI = _baseURI;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _minter);
    }

    // ------------------------------ MODIFIER -----------------------

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only Admin");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, _msgSender()), "Only Minter");
        _;
    }

    // ------------------------------ VIEW -----------------------
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "ArtGPT: URI query for nonexistent token");
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    // ------- Users Operations -------

    function order(string calldata _prompt) external payable whenNotPaused {
        Config memory _config = config;
        require(_config.mintStarted, "ArtGPT: Order is not started");
        IERC20(_config.token).universalTransferFrom(
            _msgSender(),
            address(this),
            _config.price
        );
        require(
            _publicArts.current() < _config.maxSupply,
            "ArtGPT: Order would exceed maxSupply"
        );
        prompts[_publicArts.current()] = _prompt;
        orderers[_publicArts.current()] = _msgSender();
        emit Order(_msgSender(), _publicArts.current(), _prompt);
        _publicArts.increment();
    }

    // ------- Minter Operations -------

    function mint(uint256 _tokenId) external whenNotPaused onlyMinter {
        Config memory _config = config;
        require(_tokenId < _config.maxSupply, "ArtGPT: tokenId is not valid");
        require(!_exists(_tokenId), "ArtGPT: tokenId already exist");
        _safeMint(orderers[_tokenId], _tokenId);
        emit Shipped(orderers[_tokenId], _tokenId);
    }

    // ------- Admin Operations -------

    function setBaseURI(string calldata _baseURI) external onlyAdmin {
        baseURI = _baseURI;
    }

    function flipMintState() external onlyAdmin {
        config.mintStarted = !config.mintStarted;
    }

    function withdraw() external onlyAdmin {
        uint256 balance = address(this).balance;
        Address.sendValue(payable(_msgSender()), balance);
    }

    function removeOtherERC20Tokens(address _tokenAddress, address _to)
        external
        onlyAdmin
    {
        ERC20 erc20Token = ERC20(_tokenAddress);
        require(
            erc20Token.transfer(_to, erc20Token.balanceOf(address(this))),
            "ERC20 Token transfer failed"
        );
    }

    function updateMintPrice(uint256 _price) external whenPaused onlyAdmin {
        config.price = _price;
    }

    function updatePaymentToken(address _token) external whenPaused onlyAdmin {
        config.token = _token;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

