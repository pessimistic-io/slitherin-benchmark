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

import "./Ownable.sol";
import "./ERC1967Proxy.sol";
import "./Collection.sol";

/**
 * @dev This factory creates Alexandria collections deployed as ERC1967Proxys.
 *      For more info or to publish your own Alexandria collection, visit alexandrialabs.xyz.
 */
contract CollectionFactory is Ownable {
    address public implementationAddress;

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint256 public primaryRoyaltyPercentage; // Author's primary royalty, specified in basis points, e.g. 8500 = 85%
    address public platformPayout;

    event PrimaryRoyaltyPercentageChanged(uint256 newPrimaryRoyaltyPercentage);
    event PlatformPayoutChanged(address newPlatformPayout);

    error PrimaryRoyaltyPercentageOutOfRange(
        uint256 valueSent,
        uint256 minAllowedValue,
        uint256 maxAllowedValue
    );
    error PlatformPayoutIsZeroAddress();

    event CollectionDeployed(
        address collectionAddress,
        string name,
        string symbol,
        string baseTokenURI,
        string contractURI,
        Collection.CollectionParameters collectionParameters,
        address author,
        uint256 primaryRoyaltyPercentage,
        address platformPayout
    );

    constructor(uint256 primaryRoyaltyPercentage_) {
        primaryRoyaltyPercentage = primaryRoyaltyPercentage_;
        platformPayout = msg.sender;

        // Deploy the Collection implementation contract
        implementationAddress = address(new Collection());
    }

    function deployCollection(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        string memory contractURI,
        Collection.CollectionParameters memory collectionParameters
    ) external {
        address[] memory accounts = new address[](2);
        uint256[] memory paymentSplit = new uint256[](2);

        accounts[0] = msg.sender; // author
        accounts[1] = platformPayout;
        paymentSplit[0] = primaryRoyaltyPercentage; // primaryRoyaltyPercentage is specified in basis points
        paymentSplit[1] = MAX_BASIS_POINTS - primaryRoyaltyPercentage;

        bytes memory initCalldata = abi.encodeWithSelector(
            Collection.initialize.selector,
            name,
            symbol,
            baseTokenURI,
            contractURI,
            collectionParameters,
            accounts,
            paymentSplit
        );
        ERC1967Proxy collectionProxy = new ERC1967Proxy(implementationAddress, initCalldata);

        emit CollectionDeployed(
            address(collectionProxy),
            name,
            symbol,
            baseTokenURI,
            contractURI,
            collectionParameters,
            msg.sender,
            primaryRoyaltyPercentage,
            platformPayout
        );
    }

    /**
     * @dev Sets the primary royalty percentage that the author will receive upon
     * primary sale (minting) of their book. This value is specified in basis points,
     * e.g. 8500 = 85%.
     *
     * Note that updating this value only applies to future collections deployed by
     * the factory, all currently deployed collections are not changed.
     *
     * Edge values of zero and MAX_BASIS_POINTS are NOT allowed as Collection's
     * PaymentSplitter will revert with "PaymentSplitter: shares are 0".
     */
    function setPrimaryRoyaltyPercentage(uint256 primaryRoyaltyPercentage_) external onlyOwner {
        if (!((primaryRoyaltyPercentage_ > 0) && (primaryRoyaltyPercentage_ < MAX_BASIS_POINTS)))
            revert PrimaryRoyaltyPercentageOutOfRange(primaryRoyaltyPercentage_, 0, MAX_BASIS_POINTS);
        primaryRoyaltyPercentage = primaryRoyaltyPercentage_;
        emit PrimaryRoyaltyPercentageChanged(primaryRoyaltyPercentage);
    }

    /**
     * @dev Sets the platformPayout address.
     *
     * Note that updating this value only applies to future collections deployed by
     * the factory, all currently deployed collections are not changed.
     */
    function setPlatformPayout(address platformPayout_) external onlyOwner {
        if (platformPayout_ == address(0)) revert PlatformPayoutIsZeroAddress();
        platformPayout = platformPayout_;
        emit PlatformPayoutChanged(platformPayout);
    }
}

