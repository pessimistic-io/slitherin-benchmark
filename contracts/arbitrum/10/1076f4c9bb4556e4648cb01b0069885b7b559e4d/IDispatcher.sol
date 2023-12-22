// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ICollectionData.sol";

interface IDispatcher is ICollectionData {

    event OrderDispatched(address indexed _entity, address indexed _offer, uint256 indexed _reservationId, uint256 _offerId);
    event ReservationAdded(address indexed _entity, address indexed _offer, address indexed _patron, uint256 _newReservationId, uint256 _expiry, bool  _cashPayment);
    event ReservationFulfilled(address _entity, address indexed _offer, address indexed _patron, uint256 indexed _reservationId, uint256 _offerId);
    event ReservationCancelled(address _entity, address indexed _offer, uint256 indexed _reservationId);
    event ReservationsExpirySet(uint256 _newExpiry);
    event TokenMintedForReservation(address indexed _entity, address indexed _offer, uint256 indexed _reservationId, uint256 _offerId);
    event UserContractSet(address _newUserContract);
    event Loot8CollectionFactorySet(address _newLoot8CollectionFactory);

    struct OfferContext {
        uint256 id;
        uint256 expiry;
        uint256 totalPurchases;
        uint256 activeReservationsCount;
        uint256 maxPurchase;
        uint256[] reservations;
        mapping(address => uint256) patronRecentReservation;

        // Storage Gap
        uint256[20] __gap;
    }

    struct Reservation {
        uint256 id;
        address patron;
        uint256 created;
        uint256 expiry;
        address offer;
        uint256 offerId; // Offer Collectible Token Id if Collectible was minted for this reservation
        bool cashPayment; // Flag indicating if the reservation will be paid for in cash or online
        bool cancelled;
        bool fulfilled; // Flag to indicate if the order was fulfilled
        bytes data;
        address passport; // Passport on which the offer was reserved

        // Storage Gap
        uint256[19] __gap;
    }

    function addOfferWithContext(address _offer, uint256 _maxPurchase, uint256 _expiry) external;
    function removeOfferWithContext(address _offer) external;

    function addReservation(
        address _offer,
        address _passport,
        address _patron, 
        bool _cashPayment,
        uint256 _offerId
    ) external returns(uint256 newReservationId);

    function cancelReservation(uint256 _reservationId) external;

    function reservationAddTxnInfoMint(uint256 _reservationId, bytes memory _data) external returns(uint256 offerId);

    function getReservationDetails(uint256 _reservationId) external view returns(Reservation memory);

    function getPatronRecentReservationForOffer(address _patron, address _offer) external view returns(uint256);

    function updateActiveReservationsCount() external;

    function setReservationExpiry(uint256 _newExpiry) external;

    function dispatch (
        uint256 _reservationId,
        bytes memory _data
    ) external;

    function registerUser(
        string memory _name,
        string memory _avatarURI,
        string memory _dataURI
    ) external returns (uint256 userId);

    function mintAvailableCollectibles(address _patron) external;

    function mintLinkedCollectionsTokensForHolders(address _collection) external;

    function mintLinked(address _collectible, address _patron) external;

    function getAllOffers() external view returns(address[] memory);

    function getAllReservations() external view returns(Reservation[] memory _allReservations);

    /*function getAllActiveReservations() external view returns(Reservation[] memory _activeReservations);

    function getPatronReservations(address _patron, bool _checkActive) external view returns(Reservation[] memory _patronReservations);

    function patronReservationActiveForOffer(address _patron, address _offer) external view returns(bool);

    function getActiveReservationsForEntity(address _entity) external view returns(Reservation[] memory _entityActiveReservations);*/

    function getCurrentReservationId() external view returns(uint256);

    function getReservationsForOffer(address _offer) external view returns(uint256[] memory);    
}
