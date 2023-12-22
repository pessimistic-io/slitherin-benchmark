// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import "./ILoot8MarketplaceVerification.sol";

import "./Counters.sol";
import "./ECDSA.sol";
import "./Initializable.sol";
import "./EIP712Upgradeable.sol";

contract Loot8MarketplaceVerification is ILoot8MarketplaceVerification, Initializable, EIP712Upgradeable {

    using ECDSA for bytes32;

    using Counters for Counters.Counter;

    // Mapping Signers address => A nonce counter for signatures
    mapping(address => Counters.Counter) public nonces;

    bytes32 private constant _TYPEHASH =
        keccak256('RequestValidated(address patron,address passport,address collection,uint256 tokenId,address paymentToken,uint256 price,string action,uint256 listingType,string message,uint256 nonce,uint256 expiry)');

    address public validator;
    address public governor;

    function initialize(
        address _validator,
        address _governor
    ) public initializer {
        EIP712Upgradeable.__EIP712_init('LOOT8Marketplace', '1');
        validator = _validator;
        governor = _governor;
    }

    function setValidator(address _newValidator) external {
        require(msg.sender == governor, "UNAUTHORIZED");
        address oldValidator = validator;
        validator = _newValidator;
        emit ValidatorSet(oldValidator, validator);
    }

    function getPatronCurrentNonce(address _patron) public view returns(uint256) {
        return nonces[_patron].current();
    }

    function verify(
        address _patron,
        address _passport,
        address _collection,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        string memory _action,
        ILoot8Marketplace.ListingType _listingType,
        string memory _message,
        uint256 _expiry,
        bytes memory _signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _TYPEHASH, 
                    _patron, 
                    _passport, 
                    _collection, 
                    _tokenId,
                    _paymentToken,
                    _price, 
                    keccak256(abi.encodePacked(_action)),
                    _listingType, 
                    keccak256(abi.encodePacked(_message)), 
                    nonces[_patron].current(), 
                    _expiry
                )
            )
        ).recover(_signature);
        return signer == validator;
    }

    function verifyAndUpdateNonce(
        address _patron,
        address _passport, 
        address _collection,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        string memory _action,
        ILoot8Marketplace.ListingType _listingType,
        string memory _message,
        uint256 _expiry,
        bytes memory _signature
    ) external returns (bool) {
        
        bool result = verify(
            _patron, 
            _passport, 
            _collection, 
            _tokenId,
            _paymentToken,
            _price,
            _action,
            _listingType,
            _message, 
            _expiry, 
            _signature
        );

        if(result) {
            nonces[_patron].increment();
        }

        return result;
    }
    
}
