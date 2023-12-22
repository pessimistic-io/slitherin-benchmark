// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Import necessary libraries and contracts
import "./ERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC1155Supply.sol";
import "./Strings.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";

/**
 * @title AIHumanERC1155
 * @dev AIHumanERC1155 is an ERC1155 contract, inheriting various features from OpenZeppelin contracts.
 * It includes options for minting, pausing, and setting up an allow-list. It also enables minting of multiple NFTs with different prices.
 */
contract AIHumanERC1155 is
    ERC1155,
    Ownable,
    Pausable,
    ERC1155Supply,
    ReentrancyGuard
{
    /**
     * @dev The total unique supply for the entire collection.
     * This value is used to validate token IDs in various functions.
     */
    uint256 public allCollectionUniqueSupply = 23;

    /**
     * @dev The maximum number of tokens that a single address can mint.
     * This value is used to prevent a single address from minting more than the limit.
     */
    uint256 public singleAddressMaxMint = 100;

    /**
     * @dev The maximum supply for a single NFT.
     * This value is used to prevent the total supply of a particular NFT from exceeding the limit.
     */
    uint256 public singleNftMaxSupply = 10000;

    /**
     * @dev The price for allow list minting.
     * This value is used to determine the cost of minting for addresses that are on the allow list.
     */
    uint256 public allowListPrice = 0.1 ether;

    /**
     * @dev A boolean indicating whether public minting is currently open.
     * This value is used to control access to the publicMint function.
     */
    bool public mintOpen = true;

    /**
     * @dev A boolean indicating whether allow list minting is currently open.
     * This value is used to control access to the allowListMint function.
     */
    bool public allowListMintOpen = true;

    /**
     * @dev A mapping to keep track of addresses that are on the allow list.
     * Addresses on this list have special privileges, such as access to allow list minting.
     */
    mapping(address => bool) public allowList;

    /**
     * @dev Mapping from token ID to its price.
     * Each token ID in the contract can have a price associated with it, which is stored in this mapping.
     */
    mapping(uint256 => uint256) public tokenPrices;

    /**
     * @dev Mapping from user address to token ID to the number of tokens minted by the user.
     */
    mapping(address => mapping(uint256 => uint256)) public addressTokenMinted;

    /**
     * @dev Emitted when the token URI is updated.
     */
    event URIUpdated(string newURI);

    /**
     * @dev Emitted when the price of a token ID is updated.
     */
    event TokenPriceUpdated(uint256 indexed tokenId, uint256 newPrice);

    /**
     * @dev Emitted when the allow list price is updated.
     */
    event AllowListPriceUpdated(uint256 newPrice);

    /**
     * @dev Emitted when an address is added or removed from the allow list.
     */
    event AllowListUpdated(address account, bool status);

    /**
     * @dev Emitted when the minting windows are updated.
     */
    event MintWindowsUpdated(bool mintOpen, bool allowListMintOpen);

    /**
     * @dev Emitted when a token is minted.
     */
    event TokenMinted(
        uint256 indexed id,
        uint256 amount,
        address indexed recipient
    );

    /**
     * @dev Constructs the contract, setting the base URI for all token metadata in the contract.
     * Immediately mints one of each token type to the deployer's address, resulting in `allCollectionUniqueSupply` tokens owned by the deployer.
     * Sets a default price of 0.1 ETH for each token.
     *
     * Emits a {TransferSingle} event for each token minted to the deployer.
     *
     * Requirements:
     *
     * - `_initialBaseURI` must be a non-empty string. This will be the base URI for all token metadata.
     *
     * @param _initialBaseURI The initial base URI for all tokens in the contract.
     */
    constructor(string memory _initialBaseURI) ERC1155(_initialBaseURI) {
        require(bytes(_initialBaseURI).length > 0, "URI must be non-empty");

        for (uint256 i = 0; i < allCollectionUniqueSupply; i++) {
            _mint(msg.sender, i, 1, "");
            tokenPrices[i] = 0.1 ether;
        }
    }

    /**
     * @dev Sets the price for a specific token ID.
     * Can only be called by the contract owner.
     * Emits a {TokenPriceUpdated} event.
     */
    function setTokenPrice(uint256 tokenId, uint256 price) external onlyOwner {
        require(tokenId < allCollectionUniqueSupply, "Invalid token ID");
        tokenPrices[tokenId] = price;
        emit TokenPriceUpdated(tokenId, price);
    }

    /**
     * @dev Sets the price for allow list minting.
     * Can only be called by the contract owner.
     * Emits a {AllowListPriceUpdated} event.
     */
    function setAllowListPrice(uint256 newPrice) external onlyOwner {
        allowListPrice = newPrice;
        emit AllowListPriceUpdated(newPrice);
    }

    /**
     * @dev Sets the URI for all tokens.
     * Can only be called by the contract owner.
     * Emits a {URIUpdated} event.
     */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
        emit URIUpdated(newuri);
    }

    /**
     * @dev Sets the total unique supply for the collection.
     * Can only be called by the contract owner.
     */
    function setAllCollectionUniqueSupply(uint256 newSupply)
        external
        onlyOwner
    {
        allCollectionUniqueSupply = newSupply;
    }

    /**
     * @dev Sets the maximum number of tokens that a single address can mint.
     * Can only be called by the contract owner.
     *
     * @param newMaxMint The new maximum number of tokens that a single address can mint.
     */
    function setSingleAddressMaxMint(uint256 newMaxMint) external onlyOwner {
        singleAddressMaxMint = newMaxMint;
    }

    /**
     * @dev Pauses all token transfers.
     * Can only be called by the contract owner.
     * Requirements:
     * - The caller must be the contract owner.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     * Can only be called by the contract owner.
     * Requirements:
     * - The caller must be the contract owner.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Adds addresses to the allow list.
     * Can only be called by the contract owner.
     * Emits a {AllowListUpdated} event for each address added.
     */
    function setAllowList(address[] calldata _allowList) external onlyOwner {
        for (uint64 i = 0; i < _allowList.length; i++) {
            allowList[_allowList[i]] = true;
            emit AllowListUpdated(_allowList[i], true);
        }
    }

    /**
     * @dev Removes addresses from the allow list.
     * Can only be called by the contract owner.
     * Emits a {AllowListUpdated} event for each address removed.
     */
    function removeFromAllowList(address[] calldata _allowList)
        external
        onlyOwner
    {
        for (uint64 i = 0; i < _allowList.length; i++) {
            allowList[_allowList[i]] = false;
            emit AllowListUpdated(_allowList[i], false);
        }
    }

    /**
     * @dev Edits the minting windows for public and allow list.
     * Can only be called by the contract owner.
     * Emits a {MintWindowsUpdated} event.
     */
    function editMintWindows(bool _mintOpen, bool _allowListMintOpen)
        external
        onlyOwner
    {
        mintOpen = _mintOpen;
        allowListMintOpen = _allowListMintOpen;
        emit MintWindowsUpdated(_mintOpen, _allowListMintOpen);
    }

    /**
     * @dev Function for public minting of tokens. Requires payment equal to the token's price multiplied by the amount of tokens being minted.
     * @param id The ID of the token to mint.
     * @param amount The amount of tokens to mint.
     */
    function publicMint(uint256 id, uint256 amount)
        external
        payable
        nonReentrant
    {
        require(mintOpen, "Mint is closed");
        require(tokenPrices[id] > 0, "Token ID not available for minting");
        require(
            msg.value >= tokenPrices[id] * amount,
            "Incorrect payment amount"
        );
        _mintToken(id, amount, msg.sender);
    }

    /**
     * @dev Mints tokens for the allow list.
     * The caller must send enough ETH to cover the minting cost.
     * Emits a {TokenMinted} event.
     * Requirements:
     * - Minting must be open to the allow list.
     * - The caller must be on the allow list.
     * - The caller must send enough ETH to cover the minting cost.
     * - Token id must be a valid number.
     */
    function allowListMint(uint256 id, uint256 amount)
        external
        payable
        nonReentrant
    {
        require(allowListMintOpen, "Allow list mint is closed");
        require(
            allowList[msg.sender],
            "You are not eligible for allow list mint"
        );
        require(msg.value >= allowListPrice * amount, "Not enough money sent");
        _mintToken(id, amount, msg.sender);
    }

    /**
     * @dev Internal function to handle minting logic.
     * Emits a {TokenMinted} event.
     * Requirements:
     * - The `id` must be within the range of the unique supply.
     * - Minting the amount must not exceed the maximum supply for the token.
     * - Minting the amount must not exceed the maximum allowed for the recipient address.
     */
    function _mintToken(
        uint256 id,
        uint256 amount,
        address recipient
    ) private {
        require(id < allCollectionUniqueSupply, "Nft not found");
        require(
            totalSupply(id) + amount <= singleNftMaxSupply,
            "Max supply for this NFT ID cannot be exceeded"
        );
        require(
            addressTokenMinted[recipient][id] + amount <= singleAddressMaxMint,
            "Max mint limit per address exceeded"
        );
        _mint(recipient, id, amount, "");
        addressTokenMinted[recipient][id] += amount;
        emit TokenMinted(id, amount, recipient);
    }

    /**
     * @dev Withdraws the contract balance to a given address.
     * Can only be called by the contract owner.
     */
    function withdraw(address _addr) external onlyOwner nonReentrant {
        uint256 contractBalance = address(this).balance;
        Address.sendValue(payable(_addr), contractBalance);
    }

    /**
     * @dev Returns the URI for a specific token.
     * Requirements:
     * - The token must exist.
     */
    function uri(uint256 _id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(exists(_id), "URI: nonexistent token");
        return
            string(
                abi.encodePacked(super.uri(_id), Strings.toString(_id), ".json")
            );
    }

    /**
     * @dev Mints a batch of tokens.
     * Can only be called by the contract owner.
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @dev Hook that is called before any token transfer.
     * This includes minting and burning.
     * When paused, all transfers except for those initiated by the contract owner are blocked.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

