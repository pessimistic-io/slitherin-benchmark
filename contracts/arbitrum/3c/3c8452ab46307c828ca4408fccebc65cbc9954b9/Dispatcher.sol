/**************************************************************************************************************
// This contract consolidates all functionality for managing reservations and user registrations
**************************************************************************************************************/

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";

import "./IUser.sol";
import "./IEntity.sol";
import "./IDispatcher.sol";
import "./ILoot8Token.sol";
import "./ICollectionHelper.sol";
import "./ICollectionManager.sol";
import "./ICollectionData.sol";
import "./ICollectionFactory.sol";

import "./Counters.sol";
import "./IERC721.sol";
import "./Initializable.sol";

contract Dispatcher is IDispatcher, Initializable, DAOAccessControlled {
    
    using Counters for Counters.Counter;

    // Unique IDs for new reservations
    Counters.Counter private reservationIds;

    // Unique IDs for new offers
    Counters.Counter private offerContractsIds;

    // Time after which a new reservation expires(Seconds)
    uint256 public reservationsExpiry; 
    address public loot8Token;
    address public daoWallet;
    address public userContract;
    address public loot8CollectionFactory;

    // Earliest non-expired reservation, for gas optimization
    uint256 public earliestNonExpiredIndex;

    // List of all offers
    address[] public allOffers;

    // Offer/Event wise context for each offer/event
    mapping(address => OfferContext) public offerContext;

    // Mapping ReservationID => Reservation Details
    mapping(uint256 => Reservation) public reservations;

    function initialize(
        address _authority,
        address _loot8Token,
        address _daoWallet,
        uint256 _reservationsExpiry,
        address _userContract,
        address _loot8CollectionFactory
    ) public initializer {

        DAOAccessControlled._setAuthority(_authority);
        loot8Token = _loot8Token;
        daoWallet = _daoWallet;
        reservationsExpiry = _reservationsExpiry;

        // Start ids with 1 as 0 is for existence check
        offerContractsIds.increment();
        reservationIds.increment();
        earliestNonExpiredIndex = reservationIds.current();
        userContract = _userContract;
        loot8CollectionFactory = _loot8CollectionFactory;
    }

    function addOfferWithContext(address _offer, uint256 _maxPurchase, uint256 _expiry) external {
        
        require(msg.sender == authority.getAuthorities().collectionManager, 'UNAUTHORIZED');

        OfferContext storage oc = offerContext[_offer];
        oc.id = offerContractsIds.current();
        oc.expiry = _expiry;
        oc.totalPurchases = 0;
        oc.activeReservationsCount = 0;
        oc.maxPurchase = _maxPurchase;

        allOffers.push(_offer);

        offerContractsIds.increment();
    }

    function removeOfferWithContext(address _offer) external {
        require(msg.sender == authority.getAuthorities().collectionManager, 'UNAUTHORIZED');
        require(offerContext[_offer].expiry < block.timestamp, "OFFER NOT EXPIRED");
        updateActiveReservationsCount();
        require(offerContext[_offer].activeReservationsCount == 0, "OFFER HAS ACTIVE RESERVATIONS");
        delete offerContext[_offer];
        for (uint256 i = 0; i < allOffers.length; i++) {
            if(allOffers[i] == _offer) {
                if( i < allOffers.length - 1) {
                    allOffers[i] = allOffers[allOffers.length - 1];
                }
                allOffers.pop();
            }
        }
    }

    /**
     * @notice Called to create a reservation when a patron places an order using their mobile app
     * @param _offer address Address of the offer contract for which a reservation needs to be made
     * @param _patron address
     * @param _cashPayment bool True if cash will be used as mode of payment
     * @return newReservationId Unique Reservation Id for the newly created reservation
    */
    function addReservation(
        address _offer,
        address _patron, 
        bool _cashPayment,
        uint256 _offerId
    ) external onlyForwarder
    returns(uint256 newReservationId) {

        uint256 _patronRecentReservation = offerContext[_offer].patronRecentReservation[_patron];

        require(
            reservations[_patronRecentReservation].fulfilled ||
            reservations[_patronRecentReservation].cancelled || 
            reservations[_patronRecentReservation].expiry <= block.timestamp, 'PATRON HAS AN ACTIVE RESERVATION');

        require(ICollectionManager(authority.getAuthorities().collectionManager).checkCollectionActive(_offer), "OFFER IS NOT ACTIVE");
        this.updateActiveReservationsCount();
        
        require(
            (offerContext[_offer].maxPurchase == 0 || 
            (offerContext[_offer].totalPurchases + offerContext[_offer].activeReservationsCount) < offerContext[_offer].maxPurchase),
            'MAX PURCHASE EXCEEDED'
        );
        
        offerContext[_offer].activeReservationsCount++;

        uint256 _expiry = block.timestamp + reservationsExpiry;

        newReservationId = reservationIds.current();

        uint256[20] memory __gap;
        // Create reservation
        reservations[newReservationId] = Reservation({
            id: newReservationId,
            patron: _patron,
            created: block.timestamp,
            expiry: _expiry,
            offer: _offer,
            offerId: _offerId, // 0 for normal offers. > 0 for redeemable coupons
            cashPayment: _cashPayment,
            data: "",
            cancelled: false,
            fulfilled: false,
            __gap: __gap
        });

        offerContext[_offer].patronRecentReservation[_patron] = newReservationId;

        offerContext[_offer].reservations.push(newReservationId);

        // Dispatch and fulfill a reservation for redeemable coupons that don't need bartender approval/serve
        if(_offerId > 0 &&  !_cashPayment) {
            _dispatch(newReservationId, '');
        }

        reservationIds.increment();

        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_offer).entity;

        emit ReservationAdded(_entity, _offer, _patron, newReservationId, _expiry, _cashPayment);
    }

    /**
     * @notice Called by bartender or patron to cancel a reservation
     * @param _reservationId uint256
    */
    function cancelReservation(uint256 _reservationId) external {
        
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        require(!reservations[_reservationId].fulfilled, "DISPATCHED RESERVATION");
        require(!reservations[_reservationId].cancelled, "CANCELLED RESERVATION");

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_offer).entity;
        require(
            IEntity(_entity).getBartenderDetails(_msgSender()).isActive || 
            _msgSender() == reservations[_reservationId].patron, "UNAUTHORIZED"
        );

        reservations[_reservationId].cancelled = true;
        offerContext[_offer].activeReservationsCount--;
        
        // TODO: Burn collectible if minted
        emit ReservationCancelled(_entity, _offer, _reservationId);
    }

    /**
     * @notice Mints a Collectible for a reservation and sets the offer Id in Reservation details
     * @param _reservationId uint256
     * @param _data bytes Meta data for the reservation
     * @return offerId uint256 Token Id for newly minted Collectible
    */
    function reservationAddTxnInfoMint(uint256 _reservationId, bytes memory _data) external returns(uint256 offerId) {
        require(_msgSender() == address(this) || isTrustedForwarder(msg.sender), "UNAUTHORIZED");
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_offer).entity;
        offerId = _mintCollectibles(_offer, reservations[_reservationId].patron);
        emit TokenMintedForReservation(_entity, _offer, _reservationId, offerId);
        if(offerId > 0) {
            reservations[_reservationId].offerId = offerId;
        }
        reservations[_reservationId].data = _data;
    }

    function getReservationDetails(uint256 _reservationId) public view returns(Reservation memory){
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        return reservations[_reservationId];
    }

    function getPatronRecentReservationForOffer(address _patron, address _offer) public view returns(uint256) {
        return offerContext[_offer].patronRecentReservation[_patron];
    }

    /**
     * @notice Maintenance function to cancel expired reservations and update active reservation counts
    */
    function updateActiveReservationsCount() public {

        for (uint256 i = earliestNonExpiredIndex; i < reservationIds.current(); i++) {
            
            Reservation storage reservation = reservations[i];

            if (reservation.offerId == 0) { // we cannot cancel reservations if offer token minted
                if (
                    reservation.expiry <= block.timestamp && 
                    !reservation.cancelled &&
                    !reservation.fulfilled
                ) {
                    reservation.cancelled = true;
                    if(offerContext[reservation.offer].activeReservationsCount > 0) {
                        offerContext[reservation.offer].activeReservationsCount--;
                    }
                }
            }

            // Set earliestNonExpiredIndex for next updateActiveReservationsCount call
            if(
                (
                    reservations[earliestNonExpiredIndex].cancelled ||
                    reservations[earliestNonExpiredIndex].fulfilled
                ) && (
                    reservation.expiry > block.timestamp && 
                    !reservation.cancelled && !reservation.fulfilled
                )
            ) {
                earliestNonExpiredIndex = reservation.id;
            }
            
        }
    }

    function dispatch (
        uint256 _reservationId,
        bytes memory _data
    ) public {
        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_offer).entity;
        require(IEntity(_entity).getBartenderDetails(_msgSender()).isActive, "UNAUTHORIZED");
        _dispatch(_reservationId, _data);
    }

    function _dispatch (
        uint256 _reservationId,
        bytes memory _data
    ) internal {

        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        require(!reservations[_reservationId].fulfilled, "DISPATCHED RESERVATION");
        require(!reservations[_reservationId].cancelled, "CANCELLED RESERVATION");

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(_offer).entity;

        require(offerContext[_offer].id != 0, "No Such Offer");
        address patron = reservations[_reservationId].patron;
        
        require(offerContext[_offer].patronRecentReservation[patron] == _reservationId, 'RESERVATION NOT RECENT OR ACTIVE');
        require(!reservations[_reservationId].cancelled, 'CANCELLED RESERVATION');
        require(reservations[_reservationId].expiry > block.timestamp, 'RESERVATION EXPIRED');

        uint256 _offerId;

        // Mint Collectible if not already minted
        if(reservations[_reservationId].offerId == 0) {
            _offerId = this.reservationAddTxnInfoMint(_reservationId, _data);
        }

        // Fulfill the reservation
        _fulfillReservation(_reservationId);

        emit OrderDispatched(_entity, _offer, _reservationId, _offerId);
    }

    /**
     * @notice Allows the administrator to change expiry for reservations
     * @param _newExpiry uint256 New expiry timestamp
    */
    function setReservationExpiry(uint256 _newExpiry) external onlyGovernor {
        reservationsExpiry = _newExpiry;

        emit ReservationsExpirySet(_newExpiry);
    }

    /**
     * @notice Allows the administrator to change user contract for registrations
     * @param _newUserContract address
    */
    function setUserContract(address _newUserContract) external onlyGovernor {
        userContract = _newUserContract;

        emit UserContractSet(_newUserContract);
    }

    /**
     * @notice Allows the administrator to change Loot8 collection factory contract for collections minting
     * @param _newLoot8CollectionFactory address Address of the new Loot8 collection factory contract
    */
    function setLoot8CollectionFactory(address _newLoot8CollectionFactory) external onlyGovernor {
        loot8CollectionFactory = _newLoot8CollectionFactory;

        emit Loot8CollectionFactorySet(_newLoot8CollectionFactory);
    }

    /**
     * @notice Called to complete a reservation when order is dispatched
     * @param _reservationId uint256
    */
    function _fulfillReservation(uint256 _reservationId) internal {
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        reservations[_reservationId].fulfilled = true;

        address offer = reservations[_reservationId].offer;
        offerContext[offer].activeReservationsCount--;
        offerContext[offer].totalPurchases++;

        uint256 _offerId = reservations[_reservationId].offerId;
        ICollectionManager(authority.getAuthorities().collectionManager).setCollectibleRedemption(offer, _offerId);

        uint256 rewards = ICollectionHelper(authority.collectionHelper()).calculateRewards(offer, 1);

        _mintRewards(_reservationId, rewards);

        _creditRewardsToPassport(_reservationId, rewards);

        address _entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(offer).entity;

        emit ReservationFulfilled(_entity, offer, reservations[_reservationId].patron, _reservationId, _offerId);
    }
    
    function _getOfferPassport(address _offer) internal view returns(address) {
        
        address[] memory _collections = ICollectionHelper(authority.collectionHelper()).getAllLinkedCollections(_offer);

        for(uint256 i = 0; i < _collections.length; i++) {
            if(
                ICollectionManager(authority.getAuthorities().collectionManager).getCollectionType(_collections[i]) == 
                ICollectionData.CollectionType.PASSPORT
            ) {
                return _collections[i];
            }
        }

        return address(0);

    }

    function _mintRewards(uint256 _reservationId, uint256 _rewards) internal {
        address offer = reservations[_reservationId].offer;
        address entity = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(offer).entity;

        ILoot8Token(loot8Token).mint(reservations[_reservationId].patron, _rewards);
        ILoot8Token(loot8Token).mint(daoWallet, _rewards);
        ILoot8Token(loot8Token).mint(entity, _rewards);
    }

    function _creditRewardsToPassport(uint256 _reservationId, uint256 _rewards) internal {
        address _passport = _getOfferPassport(reservations[_reservationId].offer);
        if(_passport != address(0)) {
            ICollectionManager(authority.getAuthorities().collectionManager).creditRewards(_passport, reservations[_reservationId].patron, _rewards);
        }
    }

    function registerUser(
        string memory _name,
        string memory _avatarURI,
        string memory _dataURI
    ) external onlyForwarder returns (uint256 userId) {
        
        userId = IUser(userContract).register(_name, _msgSender(), _avatarURI, _dataURI);

        _mintAvailableCollectibles(_msgSender());
    }   

    function mintAvailableCollectibles(address _patron) external onlyForwarder {
        _mintAvailableCollectibles(_patron);
    }

    /*
     * @notice Mints available passports and their linked collections
     * @param _patron address The patron to whom collections should be minted
    */
    function _mintAvailableCollectibles(address _patron) internal {
        
        IExternalCollectionManager.ContractDetails[] memory allLoot8Collections = ICollectionManager(authority.getAuthorities().collectionManager).getAllCollectionsWithChainId(CollectionType.PASSPORT, true);

        ICollectionManager collectionManager = ICollectionManager(authority.getAuthorities().collectionManager);

        for(uint256 i = 0; i < allLoot8Collections.length; i++) {

            (string[] memory points, uint256 radius) = collectionManager.getLocationDetails(allLoot8Collections[i].source);
          
            if( 
                points.length == 0 
                && radius == 0
            ) {

                (,,,,CollectionDataAdditional memory _additionCollectionData,,,,,) = collectionManager.getCollectionInfo(allLoot8Collections[i].source);

                if(!_additionCollectionData.mintWithLinkedOnly) {
                    uint256 balance = IERC721(allLoot8Collections[i].source).balanceOf(_patron);
                    if(balance == 0) {
                        _mintCollectibles(allLoot8Collections[i].source, _patron);
                    }
                }
            }
        }
    }

    function mintLinkedCollectionsTokensForHolders(address _collection) external onlyForwarder {
        
        require(ICollectionManager(authority.getAuthorities().collectionManager).checkCollectionActive(_collection), "Collection is retired");

        IUser.UserAttributes[] memory allUsers = IUser(userContract).getAllUsers(false);

        for(uint256 i=0; i < allUsers.length; i++) {
            mintLinked(_collection, allUsers[i].wallet);
        }

    }

    function _mintCollectibles(address _collection, address _patron) internal returns (uint256 collectibleId) {

        ICollectionManager collectionManager = ICollectionManager(authority.getAuthorities().collectionManager);

        collectibleId = collectionManager.mintCollectible(_patron, _collection);

        if (collectionManager.getCollectionType(_collection) == CollectionType.PASSPORT) {
            mintLinked(_collection, _patron);
        }
    }

    /**
     * @notice Mints collectibles for collections linked to a given collection
     * @notice Minting conditions:
     * @notice The patron should have a non-zero balance of the collection
     * @notice The linked collection should be active
     * @notice The linked collection should have the mintWithLinked boolean flag set to true for itself
     * @notice The patron should have a zero balance for the linked collection
     * @param _collection uint256 Collection for which linked collectibles are to be minted
     * @param _patron uint256 Mint to the same patron to which the collectible was minted
     */
    function mintLinked(address _collection, address _patron) public virtual override {

        require(
            _msgSender() == address(this) || 
            _msgSender() == authority.getAuthorities().collectionManager || 
            isTrustedForwarder(msg.sender), "UNAUTHORIZED"
        );
        
        ICollectionManager collectionManager = ICollectionManager(authority.getAuthorities().collectionManager);

        ICollectionHelper collectionHelper = ICollectionHelper(authority.collectionHelper());

        // Check if collection is active
        require(collectionManager.checkCollectionActive(_collection), "Collectible is retired");
        
        if(IERC721(_collection).balanceOf(_patron) > 0) {
            
            address[] memory linkedCollections = collectionHelper.getAllLinkedCollections(_collection);

            for (uint256 i = 0; i < linkedCollections.length; i++) {
                if(
                    collectionManager.checkCollectionActive(linkedCollections[i]) &&
                    collectionManager.getCollectionData(linkedCollections[i]).mintWithLinked &&
                    collectionManager.getCollectionChainId(linkedCollections[i]) == block.chainid &&
                    IERC721(linkedCollections[i]).balanceOf(_patron) == 0
                ) {
                    _mintCollectibles(linkedCollections[i], _patron);
                }
            }

        }
    }

    function getAllOffers() public view returns(address[] memory) {
        return allOffers;
    }

    function getCurrentReservationId() public view returns(uint256) {
        return reservationIds.current();
    }

    function getReservationsForOffer(address _offer) public view returns(uint256[] memory) {
        return offerContext[_offer].reservations;
    }
 
    function getAllReservations() external view returns(Reservation[] memory _allReservations) {

        _allReservations = new Reservation[](reservationIds.current());
        for(uint256 i = 0; i < reservationIds.current(); i++) {
            _allReservations[i] = reservations[i];
        }
    }
}
