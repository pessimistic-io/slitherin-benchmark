// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ICollectionHelper {
    event ContractURIUpdated(address _collection, string oldContractURI, string _contractURI);
    event CollectionsLinked(address indexed _collectible1, address indexed _collectible2);
    event CollectionsDelinked(address indexed _collectible1, address indexed _collectible2);

    function updateContractURI(address _collection, string memory _contractURI) external;
    function calculateRewards(address _collection, uint256 _quantity) external view returns(uint256);
    function linkCollections(address _collection1, address _collection2) external;
    function delinkCollections(address _collection1, address _collection2) external;
    function areLinkedCollections(address _collection1, address _collection2) external view returns(bool _areLinked);
    function getAllLinkedCollections(address _collection) external view returns (address[] memory);
}
