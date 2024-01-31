// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./ERC1967Proxy.sol";
import "./Collection.sol";

/**
 * CollectionFactory contract that deploys customized collection contracts
 * as ERC1967Proxys
 */
contract CollectionFactory is Ownable {
    address public implementationAddress;

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint256 public primaryRoyaltyPercentage; // Specified in basis points, e.g. 1500 = 15%
    address public primaryRoyaltyPayout;

    event PrimaryRoyaltyPercentageChanged(uint256 newPrimaryRoyaltyPercentage);
    event PrimaryRoyaltyPayoutChanged(address newPrimaryRoyaltyPayout);

    error PrimaryRoyaltyPercentageOutOfRange(
        uint256 valueSent,
        uint256 minAllowedValue,
        uint256 maxAllowedValue
    );
    error PrimaryRoyaltyPayoutIsZeroAddress();

    event CollectionDeployed(
        address collectionAddress,
        string name,
        string symbol,
        string baseTokenURI,
        string contractURI,
        Collection.CollectionParameters collectionParameters,
        address author,
        uint256 primaryRoyaltyPercentage,
        address primaryRoyaltyPayout
    );

    constructor(uint256 primaryRoyaltyPercentage_) {
        primaryRoyaltyPercentage = primaryRoyaltyPercentage_;
        primaryRoyaltyPayout = msg.sender;

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
        uint256[] memory royalties = new uint256[](2);

        accounts[0] = primaryRoyaltyPayout;
        accounts[1] = msg.sender;
        royalties[0] = primaryRoyaltyPercentage;
        royalties[1] = MAX_BASIS_POINTS - primaryRoyaltyPercentage; // primaryRoyaltyPercentage is specified in basis points

        bytes memory initCalldata = abi.encodeWithSelector(
            Collection.initialize.selector,
            name,
            symbol,
            baseTokenURI,
            contractURI,
            collectionParameters,
            accounts,
            royalties
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
            primaryRoyaltyPayout
        );
    }

    /**
     * Allow the owner to modify the primaryRoyaltyPercentage (note that updating
     * this value only applies to future collections, all currently deployed
     * collections are NOT updated).
     *
     * This value is specified in basis points, e.g. 1500 = 15%.
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
     * Allow the owner to modify the primaryRoyaltyPayout address (note that updating
     * this value only applies to future collections, all currently deployed
     * collections are NOT updated).
     */
    function setPrimaryRoyaltyPayout(address primaryRoyaltyPayout_) external onlyOwner {
        if (primaryRoyaltyPayout_ == address(0)) revert PrimaryRoyaltyPayoutIsZeroAddress();
        primaryRoyaltyPayout = primaryRoyaltyPayout_;
        emit PrimaryRoyaltyPayoutChanged(primaryRoyaltyPayout);
    }
}

