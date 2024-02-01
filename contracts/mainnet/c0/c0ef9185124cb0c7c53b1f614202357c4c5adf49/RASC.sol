// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SignedMinting.sol";

import "./ERC721A.sol";

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./Strings.sol";

contract RASC is ERC721A, Ownable, ReentrancyGuard, SignedMinting {
    using Address for address;
    using Strings for string;

    uint256 public constant MAX_SUPPLY = 9582;
    uint256 public constant NUM_PRESALE = 5000;
    uint256 public constant TEAM_RESERVED = 500;

    uint256 public presaleWalletLimit = 1;
    uint256 public walletLimit = 2;

    string public baseURI;
    bool public metadataFrozen;
    bool public preminted;
    bool public isSaleActive;
    bool public isPresaleActive;

    address public developer;

    constructor(address owner_, address signer_)
        ERC721A("Rotten Anti Social Club", "RASC")
        Ownable()
        SignedMinting(signer_)
    {
        require(owner_ != address(0), "No owner specified");

        developer = _msgSender();
        _transferOwnership(owner_);
    }

    function mint(uint256 _amount) public nonReentrant {
        require(isSaleActive, "Sale inactive");
        require(tx.origin == msg.sender, "No contracts");
        require(
            _amount + _numberMinted(msg.sender) <= walletLimit,
            "Wallet limit exceeded"
        );
        _performMint(msg.sender, _amount);
    }

    function mintPresale(uint256 _amount, bytes calldata signature)
        public
        nonReentrant
        isValidSignature(signature, msg.sender)
    {
        require(
            _amount + totalSupply() <= NUM_PRESALE + TEAM_RESERVED,
            "Presale Sold Out"
        );
        require(isPresaleActive, "Presale inactive");
        require(tx.origin == msg.sender, "No contracts");
        require(
            _amount + _numberMinted(msg.sender) <= presaleWalletLimit,
            "Wallet limit exceeded"
        );
        _performMint(msg.sender, _amount);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function numberMinted(address _address) public view returns (uint256) {
        return _numberMinted(_address);
    }

    function freezeMetadata() public onlyAuthorized {
        require(!metadataFrozen, "Metadata Frozen");
        metadataFrozen = true;
    }

    function setBaseURI(string calldata __baseURI) public onlyAuthorized {
        require(!metadataFrozen, "Metadata Frozen");
        baseURI = __baseURI;
    }

    function premint() public onlyAuthorized {
        require(!preminted, "Already preminted");
        _performMint(owner(), TEAM_RESERVED);
        preminted = true;
    }

    function adminMint(address _to, uint256 _amount) public onlyAuthorized {
        _performMint(_to, _amount);
    }

    function setIsSaleActive(bool _isSaleActive) public onlyAuthorized {
        isSaleActive = _isSaleActive;
    }

    function setIsPresaleActive(bool _isPresaleActive) public onlyAuthorized {
        isPresaleActive = _isPresaleActive;
    }

    function setWalletLimit(uint256 _walletLimit) public onlyAuthorized {
        walletLimit = _walletLimit;
    }

    function setMintingSigner(address _signer) public onlyAuthorized {
        _setMintingSigner(_signer);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _performMint(address _to, uint256 amount) private {
        require(_to != address(0), "Cannot mint to 0x0");
        require(amount > 0, "Amount cannot be 0");
        require(amount + totalSupply() <= MAX_SUPPLY, "Sold out");
        _safeMint(_to, amount);
    }

    // Modifiers
    modifier onlyAuthorized() {
        checkAuthorized();
        _;
    }

    function checkAuthorized() private view {
        require(
            _msgSender() == owner() || _msgSender() == developer,
            "Unauthorized"
        );
    }
}

