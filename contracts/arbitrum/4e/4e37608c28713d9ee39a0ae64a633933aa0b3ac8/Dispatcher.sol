// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./IUser.sol";
import "./IEntity.sol";
import "./ILoot8Token.sol";
import "./IDispatcher.sol";
import "./ICollectible.sol";
import "./IPassportFactory.sol";

import "./Counters.sol";
import "./Initializable.sol";

contract Dispatcher is IDispatcher,Initializable, DAOAccessControlled {
    
    using Counters for Counters.Counter;
    
    // Time after which a new reservation expires(Seconds)
    uint256 reservationsExpiry; 
    address public loot8Token;
    address public daoWallet;
    address public priceCalculator;
    address public userContract;
    address passportFactory;

    // Unique IDs for new reservations
    Counters.Counter private reservationIds;

    // Unique IDs for new offers
    Counters.Counter private offerContractsIds;

    // List of all offers
    address[] public allOffers;

    // Offer/Event wise context for each offer/event
    mapping(address => OfferContext) public offerContext;

    // Mapping ReservationID => Reservation Details
    mapping(uint256 => Reservation) public reservations;

    // Earliest non-expired reservation, for gas optimization
    uint256 public earliestNonExpiredIndex;

    function initialize(
        address _authority,
        address _loot8Token,
        address _daoWallet,
        address _priceCalculator,
        uint256 _reservationsExpiry,
        address _userContract,
        address _passportFactory
    ) public initializer {

        DAOAccessControlled._setAuthority(_authority);
        loot8Token = _loot8Token;
        daoWallet = _daoWallet;
        priceCalculator = _priceCalculator;
        reservationsExpiry = _reservationsExpiry;

        // Start ids with 1 as 0 is for existence check
        offerContractsIds.increment();
        reservationIds.increment();
        earliestNonExpiredIndex = reservationIds.current();
        userContract = _userContract;
        passportFactory = _passportFactory;
    }

    function addOfferWithContext(address _offer, uint256 _maxPurchase, uint256 _expiry, bool _transferable) external {
        
        require(msg.sender == address(_offer), 'UNAUTHORIZED');

        OfferContext storage oc = offerContext[_offer];
        oc.id = offerContractsIds.current();
        oc.expiry = _expiry;
        oc.transferable = _transferable;
        oc.totalPurchases = 0;
        oc.activeReservationsCount = 0;
        oc.maxPurchase = _maxPurchase;

        allOffers.push(_offer);

        offerContractsIds.increment();
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
        bool _cashPayment
    ) external onlyForwarder
    returns(uint256 newReservationId) {

        uint256 _patronRecentReservation = offerContext[_offer].patronRecentReservation[_patron];

        require(
            reservations[_patronRecentReservation].fulfilled ||
            reservations[_patronRecentReservation].cancelled || 
            reservations[_patronRecentReservation].expiry <= block.timestamp, 'PATRON HAS AN ACTIVE RESERVATION');

        require(ICollectible(_offer).isActive(), "OFFER IS NOT ACTIVE");
        this.updateActiveReservationsCount();
        
        require((offerContext[_offer].maxPurchase == 0 || (offerContext[_offer].totalPurchases + offerContext[_offer].activeReservationsCount) < offerContext[_offer].maxPurchase), 'MAX PURCHASE EXCEEDED');
        
        offerContext[_offer].activeReservationsCount++;

        uint256 _expiry = block.timestamp + reservationsExpiry;

        newReservationId = reservationIds.current();

        // Create reservation
        reservations[newReservationId] = Reservation({
            id: newReservationId,
            patron: _patron,
            expiry: _expiry,
            offer: _offer,
            offerId: 0,
            cashPayment: _cashPayment,
            data: "",
            cancelled: false,
            fulfilled: false
        });

        offerContext[_offer].patronRecentReservation[_patron] = newReservationId;

        offerContext[_offer].reservations.push(newReservationId);

        reservationIds.increment();

        address _entity = ICollectible(_offer).entity();

        emit ReservationAdded(_entity, _offer, _patron, newReservationId, _expiry, _cashPayment);
    }

    /**
     * @notice Called by bartender or patron to cancel a reservation
     * @param _reservationId uint256
    */
    function cancelReservation(uint256 _reservationId) external {
        
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectible(_offer).entity();
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
     * @notice Mints an NFT for a reservation and sets the offer Id in Reservation details
     * @param _reservationId uint256
     * @param _data bytes Meta data for the reservation
     * @return offerId uint256 Token Id for newly minted NFT
    */
    function reservationAddTxnInfoMint(uint256 _reservationId, bytes memory _data) external returns(uint256 offerId) {
        require(_msgSender() == address(this) || isTrustedForwarder(msg.sender), "UNAUTHORIZED");
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectible(_offer).entity();
        offerId = ICollectible(_offer).mint(reservations[_reservationId].patron, offerContext[_offer].expiry, offerContext[_offer].transferable);
        emit TokenMintedForReservation(_entity, _offer, _reservationId, offerId);
        
        reservations[_reservationId].offerId = offerId;
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
        uint256 earliestIdx = 0;

        if (earliestNonExpiredIndex == 0) earliestNonExpiredIndex = 1;
        for (uint256 i = earliestNonExpiredIndex; i < reservationIds.current(); i++) {
            Reservation storage reservation = reservations[i];
            
            if (reservation.offerId == 0) { // we cannot cancel reservations if offer token minted
                if (reservation.expiry <= block.timestamp && !reservation.cancelled) {
                    reservation.cancelled = true;
                    if(offerContext[reservation.offer].activeReservationsCount > 0) {
                        offerContext[reservation.offer].activeReservationsCount--;
                    }
                }
                else {
                    if (earliestIdx == 0) {
                        earliestIdx = i;
                    }
                }
            }
        }

        if (earliestIdx > 0) {
            earliestNonExpiredIndex = earliestIdx;
        }
    }

    function dispatch (
        uint256 _reservationId,
        bytes memory _data
    ) public {

        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        require(!reservations[_reservationId].fulfilled, "DISPATCHED RESERVATION");
        require(!reservations[_reservationId].cancelled, "CANCELLED RESERVATION");

        address _offer = reservations[_reservationId].offer;
        address _entity = ICollectible(_offer).entity();

        require(offerContext[_offer].id != 0, "No Such Offer");
        require(IEntity(_entity).getBartenderDetails(_msgSender()).isActive, "UNAUTHORIZED");

        address patron = reservations[_reservationId].patron;
        
        require(offerContext[_offer].patronRecentReservation[patron] == _reservationId, 'RESERVATION NOT RECENT OR ACTIVE');
        require(!reservations[_reservationId].cancelled, 'CANCELLED RESERVATION');
        require(reservations[_reservationId].expiry > block.timestamp, 'RESERVATION EXPIRED');

        uint256 _offerId;

        // Mint NFT if not already minted
        if(reservations[_reservationId].offerId == 0) {
            _offerId = this.reservationAddTxnInfoMint(_reservationId, _data);
        }

        // Fulfill the reservation
        _fulFillReservation(_reservationId);

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
     * @notice Allows the administrator to change passport factory contract for passports minting
     * @param _newPassportFactory address Address of the new passport factory contract
    */
    function setPassportFactory(address _newPassportFactory) external onlyGovernor {
        passportFactory = _newPassportFactory;

        emit PassportFactorySet(_newPassportFactory);
    }

    /**
     * @notice Called to complete a reservation when order is dispatched
     * @param _reservationId uint256
    */
    function _fulFillReservation(uint256 _reservationId) internal {
        require(reservations[_reservationId].id != 0, 'INVALID RESERVATION');
        reservations[_reservationId].fulfilled = true;

        address offer = reservations[_reservationId].offer;
        offerContext[offer].activeReservationsCount--;
        offerContext[offer].totalPurchases++;

        uint256 _offerId = reservations[_reservationId].offerId;
        ICollectible(offer).setRedemption(_offerId);

        uint256 rewards = ICollectible(offer).rewards();

        _mintRewards(_reservationId, rewards);

        _creditRewardsToPassport(_reservationId, rewards);

        address _entity = ICollectible(offer).entity();

        emit ReservationFulfilled(_entity, offer, reservations[_reservationId].patron, _reservationId, _offerId);
    }
    
    function _getOfferPassport(address _offer) internal returns(address) {
        
        address[] memory _collectibles = ICollectible(_offer).getLinkedCollectibles();

        for(uint256 i = 0; i < _collectibles.length; i++) {
            if(
                ICollectible(_collectibles[i]).collectibleType() == 
                ICollectible.CollectibleType.PASSPORT
            ) {
                return _collectibles[i];
            }
        }

        return address(0);

    }

    function _mintRewards(uint256 _reservationId, uint256 _rewards) internal {
        address offer = reservations[_reservationId].offer;
        address entity = ICollectible(offer).entity();

        ILoot8Token(loot8Token).mint(reservations[_reservationId].patron, _rewards);
        ILoot8Token(loot8Token).mint(daoWallet, _rewards);
        ILoot8Token(loot8Token).mint(entity, _rewards);
    }

    function _creditRewardsToPassport(uint256 _reservationId, uint256 _rewards) internal {
        address _passport = _getOfferPassport(reservations[_reservationId].offer);
        if(_passport != address(0)) {
            ICollectible(_passport).creditRewards(reservations[_reservationId].patron, _rewards);
        }
    }

    function registerUser(
        string memory _name,
        string memory _avatarURI,
        string memory _dataURI,
        uint256 _defaultPassportsExpiry, 
        bool _defaultPassportsTransferable
    ) external onlyForwarder returns (uint256 userId) {
        
        userId = IUser(userContract).register(_name, _msgSender(), _avatarURI, _dataURI);

        // Mint all available passports to the user
        _mintAvailablePassports(_msgSender(), _defaultPassportsExpiry, _defaultPassportsTransferable);
    }   

    function mintAvailablePassports(address _patron, uint256 _expiry, bool _transferable) external onlyForwarder {        
        _mintAvailablePassports(_patron, _expiry, _transferable);
    }

    function _mintAvailablePassports(address _patron, uint256 _expiry, bool _transferable) internal {
        
        address[] memory allPassports = IPassportFactory(passportFactory).getAllPassports();

        for(uint256 i = 0; i < allPassports.length; i++) {

            (string[] memory points, uint256 radius) = ICollectible(allPassports[i]).getLocationDetails();
            bool isActive = ICollectible(allPassports[i]).isActive();
          
            if(points.length == 0 && radius == 0 && isActive) {
                uint256 balance = ICollectible(allPassports[i]).balanceOf(_patron);
                if(balance == 0) {
                    ICollectible(allPassports[i]).mint(_patron, _expiry, _transferable);
                }
            }
        }
    }

    function mintLinkedCollectiblesForHolders(address _collectible, uint256 _expiry, bool _transferable) external onlyForwarder {
        
        require(ICollectible(_collectible).isActive(), "Collectible is retired");

        IUser.UserAttributes[] memory allUsers = IUser(userContract).getAllUsers(false);

        for(uint256 i=0; i < allUsers.length; i++) {
            this.mintLinked(_collectible, allUsers[i].wallet, _expiry, _transferable);
        }
    }

    /**
     * @notice Mints collectibles linked to a collectible
     * @notice Minting conditions:
     * @notice The patron should have a non-zero balance of the collectible
     * @notice The linked collectible should be active
     * @notice The linked collectible should have the mintWithLinked boolean flag set to true for itself
     * @notice The patron should have a zero balance for the linked collectible
     * @param _collectible uint256 Collectible for which linked collectibles are to be minted
     * @param _patron uint256 Mint to the same patron to which the collectible was minted
     * @param _expiry uint256 Inherit expiry from the collectible itself or pass custom
     * @param _transferable uint256 Inherit transfer characteristics from the collectible itself or pass custom
    */
    function mintLinked( address _collectible, address _patron, uint256 _expiry, bool _transferable) public virtual override {

        require(
            _msgSender() == address(this) || 
            _msgSender() == _collectible || 
            isTrustedForwarder(msg.sender), "UNAUTHORIZED"
        );
        
        // Check if collectible is active
        require(ICollectible(_collectible).isActive(), "Collectible is retired");
        
        address[] memory linkedCollectibles = ICollectible(_collectible).getLinkedCollectibles();

        for(uint256 i=0; i < linkedCollectibles.length; i++) {
            ICollectible linkedCollectibe = ICollectible(linkedCollectibles[i]);
            if(
                ICollectible(_collectible).balanceOf(_patron) > 0 &&
                linkedCollectibe.isActive() &&
                linkedCollectibe.mintWithLinked() &&
                linkedCollectibe.balanceOf(_patron) == 0
            ) {
                linkedCollectibe.mint(_patron, _expiry, _transferable);
            }
        }
    }
}
