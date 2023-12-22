// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ILocationBased.sol";

interface ICollectible is ILocationBased {

    event CollectibleMinted (
        uint256 _collectibleId,
        address indexed _patron,
        uint256 _expiry,
        bool _transferable,
        string _tokenURI
    );

    event CollectibleToggled(uint256 _collectibleId, bool _status);

    event CollectiblesLinked(address _collectible1, address _collectible2);

    event CollectiblesDelinked(address _collectible1, address _collectible2);

    event CreditRewardsToCollectible(uint256 indexed _collectibleId, address indexed _patron, uint256 _amount);

    event BurnRewardsFromCollectible(uint256 indexed _collectibleId, address indexed _patron, uint256 _amount);

    event RetiredCollectible(address _collectible);

    event Visited(uint256 _collectibleId);

    event FriendVisited(uint256 _collectibleId);

    event DataURIUpdated(address _collectible, string _oldDataURI, string _newDataURI);

    event SentNFT(address indexed _patron, uint16 _destinationChainId, uint256 _collectibleId);

    event ReceivedNFT(address indexed _patron, uint16 _srcChainId, uint256 _collectibleId);

    event MintWithLinkedToggled(bool _mintWithLinked);

    enum CollectibleType {
        PASSPORT,
        OFFER,
        DIGITALCOLLECTIBLE,
        BADGE,
        EVENT
    }

    struct CollectibleDetails {
        uint256 id;
        uint256 mintTime; // timestamp
        uint256 expiry; // timestamp
        bool isActive;
        bool transferable;
        int256 rewardBalance; // used for passports only
        uint256 visits; // // used for passports only
        uint256 friendVisits; // used for passports only
        // A flag indicating whether the collectible was redeemed
        // This can be useful in scenarios such as cancellation of orders
        // where the the NFT minted to patron is supposed to be burnt/demarcated
        // in some way when the payment is reversed to patron
        bool redeemed;
    }

    function mint (
        address _patron,
        uint256 _expiry,
        bool _transferable
    ) external returns (uint256);

    function isActive() external returns(bool);

    function rewards() external returns(uint256);

    function entity() external returns(address);

    function mintWithLinked() external returns(bool);

    function balanceOf(address owner) external view returns (uint256);

    // Activates/deactivates the collectible
    function toggle(uint256 _collectibleId) external returns(bool _status);

    function retire() external;

    function creditRewards(address _patron, uint256 _amount) external;

    function debitRewards(address _patron, uint256 _amount) external;

    function addVisit(uint256 _collectibleId) external;

    function addFriendsVisit(uint256 _collectibleId) external;

    function toggleMintWithLinked() external;

    function isRetired(address _patron) external view returns(bool);

    function getPatronNFT(address _patron) external view returns(uint256);

    function getNFTDetails(uint256 _nftId) external view returns(CollectibleDetails memory);

    function linkCollectible(address _collectible) external;
    
    function delinkCollectible(address _collectible) external;
    
    function getLinkedCollectibles() external returns(address[] memory);

    function collectibleType() external returns(CollectibleType);

    function getLocationDetails() external view returns(string[] memory, uint256);

    function ownerOf(uint256 tokenId) external view returns(address);

    function setRedemption(uint256 _offerId) external;
}

