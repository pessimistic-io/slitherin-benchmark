// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./IUser.sol";
import "./ICollectionHelper.sol";
import "./ICollectionManager.sol";
import "./ICollectionData.sol";
import "./IRoyaltyEngineV1.sol";
import "./ILoot8Marketplace.sol";
import "./ILoot8MarketplaceVerification.sol";

import "./IERC20.sol";
import "./IERC2981.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";

contract Loot8Marketplace is ILoot8Marketplace, Initializable, DAOAccessControlled {

    using SafeERC20 for IERC20;

    // Unique IDs for new listings
    uint256 public listingIds;
    
    // Marketplace fee for primary sale
    uint256 public mintFee; // 5% = 500 basis points

    // Marketplace fee for secondary sale
    uint256 public saleFee; // 2.5% = 250 basis points

    address public collectionManager;
    address public collectionHelper;
    address public userContract;
    address public verifier;

    // royaltyregistry.xyz Royalty engine contract on chain
    address public royaltyEngine;

    // LOOT8's receiver for marketplace fees(May be an EOA, multisig or contract)
    address public feeRecipient;

    // A message that the relayer will sign to indicate that the validation checks
    // have succeeded on Arbitrum
    string public constant validationMessage = "VALIDATION CHECKS PASSED";

    // Listings for sale on the marketplace
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public listingsByCollection;

    // Error Messages
    uint16 NOT_EXIST;
    uint16 SUSPENDED;
    uint16 RETIRED;
    uint16 INVALID_USER;
    uint16 NOT_OWNER;
    uint16 EXIST;
    uint16 LISTING_NOT_EXIST;
    uint16 TOKEN_NOT_APPROVED;
    uint16 PAYMENT_TOKEN_NOT_APPROVED;
    uint16 INSUFFICIENT_BALANCE;
    uint16 COLLECTION_NON_TRADEABLE;
    uint16 PRIVATE_TRADE_NOT_ALLOWED;
    uint16 PUBLIC_TRADE_NOT_ALLOWED;
    uint16 INVALID_VALIDATION_SIGNATURE;
    uint16 VALIDATION_SIGNATURE_EXPIRED;
    uint16 NOT_A_PASSPORT;
    uint16 COLLECTION_NOT_LINKED;
    uint16 PASSPORT_NEEDED;
    uint16 PAYMENT_TOKEN_INVALID;
    uint16 PASSPORT_NOT_OWNED;

    mapping(uint16 => string) private errorMessages;

    // Valid tokens acceptable as payment for sale
    mapping(address => bool) public validPaymentToken;

    function initialize(
        address _authority,
        address _collectionManager,
        address _userContract,
        address _verifier,
        address _royaltyEngine,
        address _feeRecipient
    ) public initializer {

        DAOAccessControlled._setAuthority(_authority);
        collectionManager = _collectionManager;
        collectionHelper = authority.collectionHelper();
        userContract = _userContract;
        verifier = _verifier;
        royaltyEngine = _royaltyEngine;
        feeRecipient = _feeRecipient;

        NOT_EXIST = 1;
        SUSPENDED = 2;
        RETIRED = 3;
        INVALID_USER = 4;
        NOT_OWNER = 5;
        EXIST = 6;
        LISTING_NOT_EXIST = 7;
        TOKEN_NOT_APPROVED = 8;
        PAYMENT_TOKEN_NOT_APPROVED = 9;
        INSUFFICIENT_BALANCE = 10;
        COLLECTION_NON_TRADEABLE = 11;
        PRIVATE_TRADE_NOT_ALLOWED = 12;
        PUBLIC_TRADE_NOT_ALLOWED = 13;
        INVALID_VALIDATION_SIGNATURE = 14;
        VALIDATION_SIGNATURE_EXPIRED = 15;
        NOT_A_PASSPORT = 16;
        COLLECTION_NOT_LINKED = 17;
        PASSPORT_NEEDED = 18;
        PAYMENT_TOKEN_INVALID = 19;
        PASSPORT_NOT_OWNED = 20;

        errorMessages[NOT_EXIST] = "COLLECTION DOES NOT EXIST";
        errorMessages[SUSPENDED] = "COLLECTIBLE SUSPENDED";
        errorMessages[RETIRED] = "COLLECTION RETIRED";
        errorMessages[INVALID_USER] = "INVALID OR BANNED USER";
        errorMessages[NOT_OWNER] = "LISTER IS NOT THE OWNER";
        errorMessages[EXIST] = "LISTING EXISTS";
        errorMessages[LISTING_NOT_EXIST] = "LISTING DOES NOT EXIST";
        errorMessages[TOKEN_NOT_APPROVED] = "TOKEN NOT APPROVED TO MARKETPLACE";
        errorMessages[PAYMENT_TOKEN_NOT_APPROVED] = "PAYMENT TOKEN NOT APPROVED TO MARKETPLACE";
        errorMessages[INSUFFICIENT_BALANCE] = "INSUFFICIENT BALANCE";
        errorMessages[COLLECTION_NON_TRADEABLE] = "COLLECTION IS NOT TRADEABLE";
        errorMessages[PRIVATE_TRADE_NOT_ALLOWED] = "PRIVATE TRADE NOT ALLOWED";
        errorMessages[PUBLIC_TRADE_NOT_ALLOWED] = "PUBLIC TRADE NOT ALLOWED";
        errorMessages[INVALID_VALIDATION_SIGNATURE] = "INVALID VALIDATION SIGNATURE";
        errorMessages[VALIDATION_SIGNATURE_EXPIRED] = "VALIDATION SIGNATURE EXPIRED";
        errorMessages[NOT_A_PASSPORT] = "NOT A PASSPORT";
        errorMessages[COLLECTION_NOT_LINKED] = "COLLECTION NOT LINKED TO PASSPORT";
        errorMessages[PASSPORT_NEEDED] = "PASSPORT IS NEEDED FOR PRIVATE LISTING";
        errorMessages[PAYMENT_TOKEN_INVALID] = "PAYMENT TOKEN IS INVALID";
        errorMessages[PASSPORT_NOT_OWNED] = "PASSPORT NOT OWNED BY PATRON";

        // Start ids with 1 as 0 is for existence check
        listingIds++;

    }

    // Allows governor to set Fees
    function setMarketPlaceFees(uint256 _mintFee, uint256 _saleFee) external onlyGovernor {
        mintFee = _mintFee;
        saleFee = _saleFee;

        emit MarketPlaceFeeSet(mintFee, saleFee);
    }

    function listingExists(address _collection, uint256 _tokenId, ListingType _listingType) public view returns(bool _exists, uint256 _listingId) {
        for(uint256 i = 0; i < listingsByCollection[_collection].length; i++) {
            uint256 listingId = listingsByCollection[_collection][i];
            if(listings[listingId].tokenId == _tokenId && listings[listingId].listingType == _listingType) {
                return (true, listingId);
            }
        }

        return (false, 0);
    }

    function _isCollectionLinkedToPassport(address _passport, address _collection) internal view returns(bool) {
        
        address[] memory passportLinkedCollections = ICollectionHelper(collectionHelper).getAllLinkedCollections(_passport);

        for(uint256 i = 0; i < passportLinkedCollections.length; i++) {
            if(passportLinkedCollections[i] == _collection) {
                break;
            }

            if(i == passportLinkedCollections.length - 1) {
                return false;
            }
            
        }

        address[] memory collectionLinkedCollections = ICollectionHelper(collectionHelper).getAllLinkedCollections(_collection);

        for(uint256 i = 0; i < collectionLinkedCollections.length; i++) {
            if(collectionLinkedCollections[i] == _passport) {
                break;
            }

            if(i == collectionLinkedCollections.length - 1) {
                return false;
            }
        }
        
        return true;
        
    }

    function checkItemValidity(address _passport, address _collection) public view returns(bool) {
        
        ICollectionManager _collectionManager = ICollectionManager(collectionManager);
        ICollectionHelper _collectionHelper = ICollectionHelper(collectionHelper);

        require(_collectionManager.isCollection(_collection), errorMessages[NOT_EXIST]);

        if(_passport != address(0)) {
            require(_collectionManager.isCollection(_passport), errorMessages[NOT_EXIST]);
            (,,,,,,,,, ICollectionData.CollectionType _collectionType) = _collectionManager.getCollectionInfo(_passport);
            require(_collectionType == ICollectionData.CollectionType.PASSPORT, errorMessages[NOT_A_PASSPORT]);
            require(_isCollectionLinkedToPassport(_passport, _collection), errorMessages[COLLECTION_NOT_LINKED]);
        }

        require(
            _collectionHelper.getMarketplaceConfig(_collection).allowMarketplaceOps, 
            errorMessages[COLLECTION_NON_TRADEABLE]
        );

        return true;
    }

    function checkTraderEligibility(
        address _patron, 
        address _passport, 
        address _collection, 
        ListingType _listingType
    ) public view returns(bool) {
        require(IUser(userContract).isValidPermittedUser(_patron), errorMessages[INVALID_USER]);
        
        ICollectionHelper _collectionHelper = ICollectionHelper(collectionHelper);
        
        if(_listingType == ListingType.PUBLIC) {
            require(
                ICollectionHelper(_collectionHelper).getMarketplaceConfig(_collection).publicTradeAllowed, 
                errorMessages[PUBLIC_TRADE_NOT_ALLOWED]
            );
        } else {
    
            require(
                _collectionHelper.getMarketplaceConfig(_collection).privateTradeAllowed,
                errorMessages[PRIVATE_TRADE_NOT_ALLOWED]
            );

            ICollectionManager _collectionManager = ICollectionManager(collectionManager);
            if(_passport != address(0) && _collectionManager.getCollectionChainId(_passport) == block.chainid) {
                require(IERC721(_passport).balanceOf(_patron) > 0, errorMessages[PASSPORT_NOT_OWNED]);
            }
        }

        return true;
    }

    function _getRoyaltyDetails(address _collection, uint256 _tokenId, uint256 _price) internal view returns(address payable[] memory _recepients, uint256[] memory _amounts) {

        if(IERC721(_collection).supportsInterface(0x2a55205a)) {
            (address _recepient, uint256 _royaltyAmount) = IERC2981(_collection).royaltyInfo(_tokenId, _price);
            _recepients = new address payable[](1);
            _recepients[0] = payable(_recepient);
            _amounts = new uint256[](1);
            _amounts[0] = _royaltyAmount;
        } else {
            (_recepients, _amounts) = IRoyaltyEngineV1(royaltyEngine).getRoyaltyView(_collection, _tokenId, _price);
        }

    }

    function verifyValidationSignature(
        address _patron,
        address _passport,
        address _collection,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        string memory _action,
        ListingType _listingType,
        uint256 _expiry,
        bytes memory _signature
    ) internal returns(bool){
        ILoot8MarketplaceVerification verifierContract = ILoot8MarketplaceVerification(verifier);

        return verifierContract.verifyAndUpdateNonce(
            _patron,
            _passport,
            _collection,
            _tokenId,
            _paymentToken,
            _price,
            _action,
            _listingType,
            validationMessage,
            _expiry,
            _signature
        );
    }

    // Allow listing an item for sale
    function listCollectible(
        address _passport,
        address _collection, 
        uint256 _tokenId,
        address _paymentToken, 
        uint256 _price, 
        bytes memory _signature,
        uint256 _expiry,
        ListingType _listingType
    ) external returns(uint256 _listingId) {

        if(_listingType == ListingType.PRIVATE) {
            require(_passport != address(0), errorMessages[PASSPORT_NEEDED]);
        }

        if(block.chainid == 42170 || block.chainid == 421614) {
            checkItemValidity(_passport, _collection);
            checkTraderEligibility(_msgSender(), _passport, _collection, _listingType);
        } else {
            require(_expiry > block.timestamp, errorMessages[VALIDATION_SIGNATURE_EXPIRED]);
            require(
                verifyValidationSignature(
                    _msgSender(), 
                    _passport, 
                    _collection, 
                    _tokenId, 
                    _paymentToken,
                    _price,
                    'list', 
                    _listingType,
                    _expiry, 
                    _signature
                ), errorMessages[INVALID_VALIDATION_SIGNATURE]);
        }

        require(validPaymentToken[_paymentToken], errorMessages[PAYMENT_TOKEN_INVALID]);
        require(IERC721(_collection).ownerOf(_tokenId) == _msgSender(), errorMessages[NOT_OWNER]);
        
        // Duplicate check
        (bool exists,) = listingExists(_collection, _tokenId, _listingType);
        require(!exists, errorMessages[EXIST]);

        // Approval check
        require(IERC721(_collection).getApproved(_tokenId) == address(this), errorMessages[TOKEN_NOT_APPROVED]);

        // Calculate creator Royalties, marketplace fees and seller share
        uint256 marketPlaceFees = (_price * saleFee) / 10000;
        (address payable[] memory _recepients, uint256[] memory _amounts) = _getRoyaltyDetails(_collection, _tokenId, _price);

        uint256 _royaltyShare;
        for(uint256 i = 0; i < _amounts.length; i++) {
            _royaltyShare = _royaltyShare + _amounts[i];
        }

        uint256 sellerShare = _price - _royaltyShare - marketPlaceFees;

        _listingId = listingIds;

        uint256[10] memory __gap;
        listings[_listingId] = Listing({
            id: _listingId,
            seller: _msgSender(),
            passport: _passport,
            collection: _collection,
            tokenId: _tokenId,
            paymentToken: _paymentToken,
            price: _price,
            sellerShare: sellerShare,
            royaltyRecipients: _recepients,
            amounts: _amounts,
            marketplaceFees: marketPlaceFees,
            listingType: _listingType,
            __gap: __gap
        });

        listingsByCollection[_collection].push(_listingId);

        listingIds++;

        emit ItemListedForSale(_listingId, _collection, _tokenId, _paymentToken, _price, _listingType);
    }

    function _delistCollectible(uint256 _listingId, address _collection, uint256 _tokenId) internal { 

        for(uint256 i = 0; i < listingsByCollection[_collection].length; i++) {

            if(listingsByCollection[_collection][i] == _listingId) { 
                if(i < listingsByCollection[_collection].length - 1) {
                    listingsByCollection[_collection][i] = listingsByCollection[_collection][listingsByCollection[_collection].length - 1];
                }
                listingsByCollection[_collection].pop();
            }
        }

        delete listings[_listingId];

        emit ItemDelisted(_listingId, _collection, _tokenId);

    }

    // Allow delisting an item
    function delistCollectible(uint256 _listingId) public {
        require(listings[_listingId].id > 0, errorMessages[LISTING_NOT_EXIST]);
        Listing memory listing = listings[_listingId];
        address collection = listing.collection;
        uint256 tokenId = listing.tokenId;

        require(IERC721(collection).ownerOf(tokenId) == _msgSender(), errorMessages[NOT_OWNER]);

        _delistCollectible(_listingId, collection, tokenId);

    }

    function _exchangeTokens(address _buyer, Listing memory _listing) internal {
        address paymentToken = _listing.paymentToken;
        IERC20(paymentToken).safeTransferFrom(_buyer, feeRecipient, _listing.marketplaceFees);
        
        address payable[] memory royaltyRecipients = _listing.royaltyRecipients;

        for(uint256 i = 0; i < royaltyRecipients.length; i++) {
            if(royaltyRecipients[i] != address(0)) {
                IERC20(paymentToken).safeTransferFrom(_buyer, royaltyRecipients[i], _listing.amounts[i]);
            }
        }
        
        IERC20(paymentToken).safeTransferFrom(_buyer, _listing.seller, _listing.sellerShare);
        IERC721(_listing.collection).safeTransferFrom(_listing.seller, _buyer, _listing.tokenId);
    }

    // Allows a buyer to buy a token listed for sale
    function buy(uint256 _listingId, bytes memory _signature, uint256 _expiry) external {
        require(listings[_listingId].id > 0, errorMessages[LISTING_NOT_EXIST]);
        Listing memory listing = listings[_listingId];
        address collection = listing.collection;
        address passport = listing.passport;
        uint256 tokenId = listing.tokenId;
        address paymentToken = listing.paymentToken;
        uint256 price = listing.price;
        ListingType listingType = listing.listingType;

        require(validPaymentToken[paymentToken], "PAYMENT TOKEN IS INVALID");

        if(block.chainid == 42170 || block.chainid == 421614) {
            checkItemValidity(passport, collection);   
            checkTraderEligibility(_msgSender(), passport, collection, listingType);
        } else {
            require(_expiry > block.timestamp, errorMessages[VALIDATION_SIGNATURE_EXPIRED]);
            require(
                verifyValidationSignature(
                    _msgSender(), 
                    passport, 
                    collection, 
                    tokenId,
                    paymentToken,
                    price,
                    'buy',
                    listingType,
                    _expiry, 
                    _signature
                ), errorMessages[INVALID_VALIDATION_SIGNATURE]
            );
        }

        require(IERC20(paymentToken).balanceOf(_msgSender()) >= price, errorMessages[INSUFFICIENT_BALANCE]);

        require(
            IERC20(paymentToken).allowance(_msgSender(), address(this)) >= price, 
            errorMessages[PAYMENT_TOKEN_NOT_APPROVED]
        );

        _delistCollectible(_listingId, collection, tokenId);

        _exchangeTokens(_msgSender(), listing);

        emit ItemSold(collection, tokenId);

    }

    function getAllListingsForCollection(address _collection) public view returns(Listing[] memory _listings) {
        uint256[] memory _listingsByCollection = listingsByCollection[_collection];
        _listings = new Listing[](_listingsByCollection.length);
        for(uint256 i = 0; i < _listingsByCollection.length; i++) {
            _listings[i] = listings[_listingsByCollection[i]];
        }
    }

    function addPaymentToken(address _token) external onlyGovernor {
        validPaymentToken[_token] = true;
        emit AddedPaymentToken(_token);
    }

    function removePaymentToken(address _token) external onlyGovernor {
        delete validPaymentToken[_token];
        emit RemovedPaymentToken(_token);
    }

    function getListingById(uint256 _listingId) public view returns(Listing memory _listing) {
        return listings[_listingId];
    }
}
