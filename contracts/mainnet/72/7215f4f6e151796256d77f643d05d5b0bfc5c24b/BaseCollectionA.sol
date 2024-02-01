// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Simplr
pragma solidity 0.8.11;

import "./ERC721AUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./StringsUpgradeable.sol";

/// @title Base CollectionA
/// @author Chain Labs
/// @notice Base contract for CollectionA
/// @dev Uses ERC721A (developed by azuki) as NFT standard
contract BaseCollectionA is
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721AUpgradeable
{
    //------------------------------------------------------//
    //
    //  Storage
    //
    //------------------------------------------------------//
    /// @notice Maximum tokens that can ever exist
    /// @dev maximum tokens that can be minted
    /// @return maximumTokens maximum number of tokens
    uint256 public maximumTokens;

    /// @notice Maximum tokens that can be bought per transaction in public sale
    /// @dev max mint/buy limit in public sale
    /// @return maxPurchase mint limit per transaction in public sale
    uint256 public maxPurchase;

    /// @notice Maximum tokens an account can buy/mint in public sale
    /// @dev maximum tokens an account can buy/mint in public sale
    /// @return maxHolding maximum tokens an account can hold in public sale
    uint256 public maxHolding;

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @return price the return variables of a contract’s function state variable
    uint256 public price;

    /// @notice timestamp when public (main) sale starts
    /// @dev public sale starts automatically at this time
    /// @return publicSaleStartTime timestamp when public sale starts
    uint256 public publicSaleStartTime;

    /// @notice Base URI for assets
    /// @dev this state accounts for both placeholer media as well as revealed media
    /// @return projectURI base URI for assets
    string public projectURI;

    /// @notice IPFS CID of JSON file collection metadata
    /// @dev The JSON file is created when the Simplr Collection form is filled and is used by the interface
    /// @return metadata IPFS CID
    string public metadata;

    /// @notice number of reserved tokens
    /// @dev this value is set in Reserveable contract
    /// @return reservedTokens number of tokens reserved
    uint256 public reservedTokens;

    /// @notice Stores number of tokens minted by an account
    /// @dev mapping of accounts to tokens minted by the account
    /// @return tokensMintedByAccount number of tokens minted
    mapping(address => uint256) public tokensMinted;

    //------------------------------------------------------//
    //
    //  Events
    //
    //------------------------------------------------------//

    event MetadataUpdated(string indexed metadata);

    event PriceUpdated(uint256 newPrice);

    event MaxPurchaseUpdated(uint256 newMaxPurchase);

    event MaxHoldingUpdated(uint256 newMaxHolding);

    event Minted(address indexed receiver, uint256 quantity);

    //------------------------------------------------------//
    //
    //  Setup
    //
    //------------------------------------------------------//

    /// @notice setup states of public sale and collection constants
    /// @dev internal method to setup base collection
    /// @param _name Collection Name
    /// @param _symbol Collection Symbol
    /// @param _admin admin address
    /// @param _maximumTokens maximum number of tokens
    /// @param _maxPurchase maximum number of tokens that can be bought per transaction in public sale
    /// @param _maxHolding maximum number of tokens an account can hold in public sale
    /// @param _price price per NFT token during public sale.
    /// @param _publicSaleStartTime public sale start timestamp
    /// @param _projectURI URI for collection media and assets
    function setupBaseCollection(
        string memory _name,
        string memory _symbol,
        address _admin,
        uint256 _maximumTokens,
        uint16 _maxPurchase,
        uint16 _maxHolding,
        uint256 _price,
        uint256 _publicSaleStartTime,
        string memory _projectURI
    ) internal {
        require(_admin != address(0), "BC:001");
        require(_maximumTokens != 0, "BC:002");
        require(
            _maximumTokens >= _maxHolding && _maxHolding >= _maxPurchase,
            "BC:003"
        );
        __Ownable_init();
        __Pausable_init();
        __ERC721A_init(_name, _symbol);
        _transferOwnership(_admin);
        maximumTokens = _maximumTokens;
        maxPurchase = _maxPurchase;
        maxHolding = _maxHolding;
        price = _price;
        publicSaleStartTime = _publicSaleStartTime;
        projectURI = _projectURI;
    }

    //------------------------------------------------------//
    //
    //  Owner only functions
    //
    //------------------------------------------------------//

    /// @notice updates the collection details (not collection assets)
    /// @dev updates the IPFS CID that points to new collection details
    /// @param _metadata new IPFS CID with updated collection details
    function setMetadata(string memory _metadata) external {
        // can only be invoked before setup or by owner after setup
        require(!isSetupComplete() || msg.sender == owner(), "BC:004");
        require(bytes(_metadata).length != 0, "BC:005");
        metadata = _metadata;
        emit MetadataUpdated(_metadata);
    }

    /// @notice Pause sale of tokens
    /// @dev pause all the open access methods like buy and presale buy
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice unpause sale of tokens
    /// @dev unpause all the open access methods like buy and presale buy
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /// @notice Change main sale price
    /// @dev only owner can update the main sale price
    /// @param _newPrice new price
    function setPrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;
        emit PriceUpdated(_newPrice);
    }

    /// @notice Change number of tokens that be minted in one transaction
    /// @dev only owner can update maximum purchase limit per transaction
    /// @param _newMaxPurchase new maximum purchase limit
    function setMaxPurchase(uint16 _newMaxPurchase) external onlyOwner {
        maxPurchase = _newMaxPurchase;
        emit MaxPurchaseUpdated(_newMaxPurchase);
    }

    /// @notice Change number of tokens that be minted by an account
    /// @dev only owner can update maximum holding limit per account
    /// @param _newMaxHolding new maximum holding limit
    function setMaxHolding(uint16 _newMaxHolding) external onlyOwner {
        maxHolding = _newMaxHolding;
        emit MaxHoldingUpdated(_newMaxHolding);
    }

    //------------------------------------------------------//
    //
    //  Public function
    //
    //------------------------------------------------------//

    /// @notice buy during public sale
    /// @dev method to buy during public sale without affiliate
    /// @param _buyer address of buyer
    /// @param _quantity number of tokens to buy/mint
    function buy(address _buyer, uint256 _quantity) external payable virtual {
        _buy(_buyer, _quantity);
    }

    /// @notice check if public sale is active or not
    /// @dev it compares start time stamp with current time and check if sold or not
    /// @return isSaleActive a boolean, true - sale active, false - sale inactive
    function isSaleActive() public view returns (bool) {
        return
            block.timestamp >= publicSaleStartTime &&
            totalSupply() != maximumTokens;
    }

    /// @notice checks if setup is complete
    /// @dev if constants are set, setup is complete
    /// @return boolean checks if setup is complete
    function isSetupComplete() public view virtual returns (bool) {
        return maximumTokens != 0 && publicSaleStartTime != 0;
    }

    //------------------------------------------------------//
    //
    //  Internal function
    //
    //------------------------------------------------------//

    /// @notice internal method to buy during public sale
    /// @dev method to buy during public sale to be used with or without affiliate
    /// @param _buyer address of buyer
    /// @param _quantity number of tokens to buy/mint
    function _buy(address _buyer, uint256 _quantity) internal whenNotPaused {
        require(isSaleActive(), "BC:010");
        uint256 tokensMintedByUser = tokensMinted[_buyer];
        require(msg.value == (price * _quantity), "BC:011");
        require(_quantity <= maxPurchase, "BC:012");
        require(tokensMintedByUser + _quantity <= maxHolding, "BC:013");
        tokensMinted[_buyer] = tokensMintedByUser + _quantity;
        _manufacture(_buyer, _quantity);
    }

    /// @notice mints amount of tokens to an account
    /// @dev it mints tokens to an account doing sanity check of not crossing maximum tokens limit
    /// @param _receiver address of buyer
    /// @param _quantity amount of tokens to be minted
    function _manufacture(address _receiver, uint256 _quantity) internal {
        require(totalSupply() + _quantity <= maximumTokens, "BC:014");
        _safeMint(_receiver, _quantity);
        emit Minted(_receiver, _quantity);
    }

    /// @inheritdoc ERC721AUpgradeable
    function _baseURI() internal view virtual override returns (string memory) {
        return projectURI;
    }

    /// @inheritdoc	ERC721AUpgradeable
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
}

