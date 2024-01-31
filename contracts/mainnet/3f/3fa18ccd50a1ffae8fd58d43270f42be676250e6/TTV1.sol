// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC721PausableUpgradeable.sol";
import "./MintingSalesUpgradeable.sol";
import "./WhitelistUpgradeable.sol";

contract TTV1 is
    Initializable,
    ERC721PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    MintingSalesUpgradeable,
    WhitelistUpgradeable,
    UUPSUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using StringsUpgradeable for uint256;

    uint256 private _airdropIdx;
    string private _baseTokenURI;

    event Airdrop(address account, uint256 tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        uint256 airdropIdx_
    ) 
        public initializer
    {
        __ERC721_init(name_, symbol_);
        __ERC721Pausable_init();
        __MintingSales_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _baseTokenURI = baseTokenURI_;
        _airdropIdx = airdropIdx_;
    }

    function version() external pure virtual returns(string memory) {
        return "1.0.0";
    }

    function addWhitelist(address account, uint256 amount) external virtual onlyOwner {
        _addWhitelist(account, amount);
    }

    function addWhitelistBatch(address[] calldata accountList, uint256[] calldata amountList) external virtual onlyOwner {
        _addWhitelistBatch(accountList, amountList);
    }

    function setupMinting(
        uint256 mintStartIndex,
        uint256 maxMintingAmount,
        uint64 mintStartTimestamp,
        uint64 mintEndTimestamp,        
        uint8 mintLimitPerOnce,
        uint8 whitelistLimitPerOnce

    )
        external virtual onlyOwner
    {
        _setupMinting(
            mintStartIndex,
            maxMintingAmount,
            mintStartTimestamp,
            mintEndTimestamp,
            mintLimitPerOnce,
            whitelistLimitPerOnce
        );
    }

    function airdrop(address[] calldata accountList) external virtual onlyOwner {
        for (uint256 i = 0; i < accountList.length; i++) {
            uint256 tokenId = currentAirdropIdx();
            _mint(accountList[i], tokenId);
            _increaseAirdropIdx();

            emit Airdrop(accountList[i], tokenId);
        }
    }

    function publicMinting(uint8 requestedCount)
        external
        virtual
        nonReentrant
        salesValidator(requestedCount, false)
    {
        for (uint256 i = 0; i < requestedCount; i++) {
            uint256 tokenId = salesIndex();
            _safeMint(_msgSender(), tokenId);
            _mintCounting();
        }
    }

    function whitelistMinting(uint8 requestedCount)
        external
        virtual
        onlyWhitelist
        nonReentrant
        salesValidator(requestedCount, true)
    {
        for (uint256 i = 0; i < requestedCount; i++) {
            uint256 tokenId = salesIndex();
            _safeMint(_msgSender(), tokenId);
            _mintCounting();
        }

        _usedWhitelist(_msgSender());
    }
    
    function burn(address from, uint256 tokenId) external virtual {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC721: caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    function reveal(string calldata revealURI) external virtual onlyOwner {
        _baseTokenURI = revealURI;
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    function currentAirdropIdx() public view virtual returns (uint256) {
        return _airdropIdx;
    }

    function tokenURI(uint256 tokenId) public view override virtual returns (string memory) {
        return string(abi.encodePacked(_baseURI(), tokenId.toString(), ".json"));
    }

    function _baseURI() internal view override virtual returns (string memory) {
        return _baseTokenURI;
    }

    function _increaseAirdropIdx() internal virtual {
        _airdropIdx++;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
