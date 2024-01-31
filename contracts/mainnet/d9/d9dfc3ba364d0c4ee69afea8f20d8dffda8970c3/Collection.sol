// SPDX-License-Identifier: MIT
/* 
      ___                     ___         ___         ___         ___        _____        ___                   ___     
     /  /\                   /  /\       /__/|       /  /\       /__/\      /  /::\      /  /\      ___        /  /\    
    /  /::\                 /  /:/_     |  |:|      /  /::\      \  \:\    /  /:/\:\    /  /::\    /  /\      /  /::\   
   /  /:/\:\  ___     ___  /  /:/ /\    |  |:|     /  /:/\:\      \  \:\  /  /:/  \:\  /  /:/\:\  /  /:/     /  /:/\:\  
  /  /:/~/::\/__/\   /  /\/  /:/ /:/_ __|__|:|    /  /:/~/::\ _____\__\:\/__/:/ \__\:|/  /:/~/:/ /__/::\    /  /:/~/::\ 
 /__/:/ /:/\:\  \:\ /  /:/__/:/ /:/ //__/::::\___/__/:/ /:/\:/__/::::::::\  \:\ /  /:/__/:/ /:/__\__\/\:\__/__/:/ /:/\:\
 \  \:\/:/__\/\  \:\  /:/\  \:\/:/ /:/  ~\~~\::::\  \:\/:/__\\  \:\~~\~~\/\  \:\  /:/\  \:\/:::::/  \  \:\/\  \:\/:/__\/
  \  \::/      \  \:\/:/  \  \::/ /:/    |~~|:|~~ \  \::/     \  \:\  ~~~  \  \:\/:/  \  \::/~~~~    \__\::/\  \::/     
   \  \:\       \  \::/    \  \:\/:/     |  |:|    \  \:\      \  \:\       \  \::/    \  \:\        /__/:/  \  \:\     
    \  \:\       \__\/      \  \::/      |  |:|     \  \:\      \  \:\       \__\/      \  \:\       \__\/    \  \:\    
     \__\/                   \__\/       |__|/       \__\/       \__\/                   \__\/                 \__\/    
 */
pragma solidity ^0.8.16;

import "./ERC721Upgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./PaymentSplitterUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./RevokableDefaultOperatorFiltererUpgradeable.sol";

/**
 * @dev This is an Alexandria collection.
 *      For more info or to publish your own Alexandria collection, visit alexandrialabs.xyz.
 */
contract Collection is
    ERC721Upgradeable,
    ERC2981Upgradeable,
    AccessControlEnumerableUpgradeable,
    PaymentSplitterUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    RevokableDefaultOperatorFiltererUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    // Roles for Access Control
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant AVAILABLE_TO_MINT_ROLE = keccak256("AVAILABLE_TO_MINT_ROLE");
    bytes32 public constant PRICE_ROLE = keccak256("PRICE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    string public baseTokenURI;

    // Collection-level metadata for OpenSea (https://docs.opensea.io/docs/contract-level-metadata)
    string public contractURI;

    struct CollectionParameters {
        uint256 totalSupply;
        uint256 availableToMintDate;
        uint256 price;
        uint256 authorReserve;
        uint256 walletLimit; // Set to 0 for unlimited
        uint96 secondaryRoyaltyPercentage; // Specified in basis points, e.g. 700 = 7%
    }
    CollectionParameters public collectionParameters;

    uint256 public primaryRoyaltyPercentage; // Author's primary royalty, specified in basis points, e.g. 8500 = 85%

    address public author;
    address public platformPayout;

    // Events to indicate collection parameters have been changed
    event AvailableToMintDateChanged(uint256 newAvailableToMintDate);
    event PriceChanged(uint256 newPrice);

    // Custom errors for reverts related to availableToMint
    error NotYetAvailableToMint(uint256 availableToMintDate);
    error AlreadyAvailableToMint();

    // Custom errors for reverts during minting and transfers
    error SoldOut();
    error WalletLimitExceeded(uint256 tokensRequested, uint256 tokensInWallet, uint256 walletLimit);
    error NotEnoughRemaining(uint256 tokensRequested, uint256 tokensRemaining);
    error IncorrectPaymentAmount(uint256 amountSent, uint256 amountRequired);

    // Custom error for payments release
    error NotAuthorizedToReleasePayment(address sender, address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        string memory contractURI_,
        CollectionParameters memory collectionParameters_,
        address[] memory accounts_,
        uint256[] memory paymentSplit_
    ) external initializer {
        __ERC721_init(name_, symbol_);
        __ERC2981_init();
        __AccessControlEnumerable_init();
        __PaymentSplitter_init(accounts_, paymentSplit_);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __RevokableDefaultOperatorFilterer_init();

        baseTokenURI = baseTokenURI_;
        contractURI = contractURI_;
        collectionParameters = collectionParameters_;
        author = accounts_[0];
        platformPayout = accounts_[1];
        primaryRoyaltyPercentage = paymentSplit_[0];

        // Set the secondary royalty per ERC2981
        _setDefaultRoyalty(author, collectionParameters.secondaryRoyaltyPercentage);

        _grantRole(DEFAULT_ADMIN_ROLE, author);
        _grantRole(UPGRADER_ROLE, author);
        _grantRole(UPGRADER_ROLE, platformPayout);
        _grantRole(PAUSER_ROLE, author);
        _grantRole(PAUSER_ROLE, platformPayout);
        _grantRole(AVAILABLE_TO_MINT_ROLE, author);
        _grantRole(PRICE_ROLE, author);

        // Mint the author's reserve
        for (uint256 i = 0; i < collectionParameters.authorReserve; i++) {
            _safeMint(author);
        }
    }

    /**
     * @dev the wallet limit is in force only during live minting, and does not
     * apply to the author. A walletLimit value of zero indicates unlimited.
     */
    modifier onlyWalletLimitNotExceeded(uint256 tokens, address to) {
        if (
            (remainingSupply() != 0) &&
            (collectionParameters.walletLimit != 0) &&
            (to != author) &&
            (tokens + balanceOf(to) > collectionParameters.walletLimit)
        ) revert WalletLimitExceeded(tokens, balanceOf(to), collectionParameters.walletLimit);
        _;
    }

    function mint(uint256 tokens, address to) external payable onlyWalletLimitNotExceeded(tokens, to) {
        if (!availableToMint()) revert NotYetAvailableToMint(collectionParameters.availableToMintDate);
        if (remainingSupply() == 0) revert SoldOut();
        if (tokens > remainingSupply()) revert NotEnoughRemaining(tokens, remainingSupply());
        if (msg.value != collectionParameters.price * tokens)
            revert IncorrectPaymentAmount(msg.value, collectionParameters.price * tokens);

        for (uint256 i = 0; i < tokens; i++) {
            _safeMint(to);
        }
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyWalletLimitNotExceeded(1, to) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyWalletLimitNotExceeded(1, to) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override onlyWalletLimitNotExceeded(1, to) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function remainingSupply() public view returns (uint256) {
        return collectionParameters.totalSupply - _tokenIdCounter.current();
    }

    function availableToMint() public view returns (bool) {
        return block.timestamp >= collectionParameters.availableToMintDate;
    }

    /**
     * @dev allow the author to update the availableToMintDate if they prefer to manually
     * control the actual moment their books go on sale
     *
     * Set this value to zero to shortcut any previous future release date and
     * make the collection available to mint immediately
     *
     * Set the date further into the future to extend the release date
     *
     * If the collection is already available to mint, this value can no longer
     * be updated and we revert with an error.
     */
    function setAvailableToMintDate(uint256 newAvailableToMintDate)
        external
        onlyRole(AVAILABLE_TO_MINT_ROLE)
    {
        if (availableToMint()) revert AlreadyAvailableToMint();
        collectionParameters.availableToMintDate = newAvailableToMintDate;
        emit AvailableToMintDateChanged(newAvailableToMintDate);
    }

    function setPrice(uint256 newPrice) external onlyRole(PRICE_ROLE) {
        collectionParameters.price = newPrice;
        emit PriceChanged(newPrice);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Implement the Ownable.owner() function here because it is required by OpenSea to allow
     *      the author to edit their collection there. OpenSea uses Ownable only and NOT AccessControl
            for verifying ownershop.
     *
     * @return The AccessControl equivalent of Ownable's owner, which is holder of the
     *         DEFAULT_ADMIN_ROLE.
     */
    function owner() public view override returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    /**
     * Internal functions
     */

    function _safeMint(address to) internal {
        _tokenIdCounter.increment(); // tokenIds start at 1
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    // Here is where Pausable hooks into mint and transfers
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * PaymentSplitter overrides
     */
    function release(address payable account) public override {
        if (msg.sender != account) revert NotAuthorizedToReleasePayment(msg.sender, account);
        super.release(account);
    }

    /**
     * Function override required by Solidity
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC2981Upgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

