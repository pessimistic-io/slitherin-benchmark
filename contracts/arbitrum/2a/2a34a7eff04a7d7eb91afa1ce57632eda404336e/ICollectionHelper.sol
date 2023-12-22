// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ICollectionHelper {
    event ContractURIUpdated(address _collection, string oldContractURI, string _contractURI);
    event CollectionsLinked(address indexed _collectible1, address indexed _collectible2);
    event CollectionsDelinked(address indexed _collectible1, address indexed _collectible2);
    event TradeablitySet(address _collection, bool _privateTradeAllowed, bool _publicTradeAllowed);
    event MarketplaceOpsSet(address _collection, bool _allowMarketplaceOps);

    struct MarketplaceConfig {
        // Is the collection tradeable on a private marketplace
        // Entity Admin may choose to allow or not allow a collection to be traded privately
        bool privateTradeAllowed;

        // Is the collection tradeable on a public marketplace
        // Entity Admin may choose to allow or not allow a collection to be traded publicly
        bool publicTradeAllowed;

        // Is this collection allowed to be traded on the Loot8 marketplace.
        // Governor may choose to allow or not allow a collection to be traded on LOOT8
        bool allowMarketplaceOps;

        uint256[20] __gap;
    }

    function updateContractURI(address _collection, string memory _contractURI) external;
    function calculateRewards(address _collection, uint256 _quantity) external view returns(uint256);
    function linkCollections(address _collection1, address[] calldata _arrayOfCollections) external;
    function delinkCollections(address _collection1, address _collection2) external;
    function areLinkedCollections(address _collection1, address _collection2) external view returns(bool _areLinked);
    function getAllLinkedCollections(address _collection) external view returns (address[] memory);
    function setTradeablity(address _collection, bool _privateTradeAllowed, bool _publicTradeAllowed) external;
    function setAllowMarkeplaceOps(address _collection, bool _allowMarketplaceOps) external;
    function getMarketplaceConfig(address _collection) external view returns(MarketplaceConfig memory);
}
