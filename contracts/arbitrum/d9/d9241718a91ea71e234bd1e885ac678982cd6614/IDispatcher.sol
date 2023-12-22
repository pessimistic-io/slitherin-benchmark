// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IDispatcher {

    event OrderDispatched(address indexed _entity, address indexed _offer, uint256 indexed _reservationId, uint256 _offerId);
    event ReservationAdded(address indexed _entity, address indexed _offer, address indexed _patron, uint256 _newReservationId, uint256 _expiry, bool  _cashPayment);
    event ReservationFulfilled(address _entity, address indexed _offer, address indexed _patron, uint256 indexed _reservationId, uint256 _offerId);
    event ReservationCancelled(address _entity, address indexed _offer, uint256 indexed _reservationId);
    event ReservationsExpirySet(uint256 _newExpiry);
    event TokenMintedForReservation(address indexed _entity, address indexed _offer, uint256 indexed _reservationId, uint256 _offerId);
    event UserContractSet(address _newUserContract);
    event PassportFactorySet(address _newPassportFactory);

    struct OfferContext {
        uint256 id;
        uint256 expiry;
        bool transferable;
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
        uint256 offerId; // Offer NFT Token Id if NFT was minted for this reservation
        bool cashPayment; // Flag indicating if the reservation will be paid for in cash or online
        bool cancelled;
        bool fulfilled; // Flag to indicate if the order was fulfilled
        bytes data;

        // Storage Gap
        uint256[20] __gap;
    }

    function addOfferWithContext(address _offer, uint256 _maxPurchase, uint256 _expiry, bool _transferable) external;

    function addReservation(
        address _offer,
        address _patron, 
        bool _cashPayment
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
        string memory _dataURI, 
        uint256 _defaultPassportsExpiry, 
        bool _defaultPassportsTransferable
    ) external returns (uint256 userId);

    function mintAvailablePassports(address _patron, uint256 _expiry, bool _transferable) external;

    function mintLinkedCollectiblesForHolders(address _collectible, uint256 _expiry, bool _transferable) external; 

    function mintLinked( address _collectible, address _patron, uint256 _expiry, bool _transferable) external;

    function getAllOffers() external view returns(address[] memory);

    function priceCalculator() external view returns(address);

    function getAllReservations() external view returns(Reservation[] memory _allReservations);

    function getAllActiveReservations() external view returns(Reservation[] memory _activeReservations);

    function getPatronReservations(address _patron, bool _checkActive) external view returns(Reservation[] memory _patronReservations);

    function patronReservationActiveForOffer(address _patron, address _offer) external view returns(bool);

    function getActiveReservationsForEntity(address _entity) external view returns(Reservation[] memory _entityActiveReservations);

}
