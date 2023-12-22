// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableUpgradeable, Initializable} from "./OwnableUpgradeable.sol";
import {IERC165Upgradeable} from "./IERC165Upgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {AddressUpgradeable} from "./AddressUpgradeable.sol";

import {UD60x18, ud, convert} from "./UD60x18.sol";

import {ECDSAUpgradeable} from "./ECDSAUpgradeable.sol";
import {EIP712Upgradeable} from "./draft-EIP712Upgradeable.sol";

import {IMagicDomainRegistrar} from "./IMagicDomainRegistrar.sol";
import {IMagicDomainReverseRegistrar} from "./IMagicDomainReverseRegistrar.sol";
import {IMagicDomainRegistrarController} from "./IMagicDomainRegistrarController.sol";
import {LibStrings} from "./LibStrings.sol";

import "./console2.sol";

/**
 * @dev A registrar controller for registering handling registration/renewals
 */
contract MagicDomainRegistrarController is OwnableUpgradeable, EIP712Upgradeable, IMagicDomainRegistrarController, IERC165Upgradeable {
    using LibStrings for *;
    using AddressUpgradeable for address;
    using ECDSAUpgradeable for bytes32;

    bytes32 public constant REGISTERARGS_TYPE_HASH
        = keccak256("RegisterArgs(string name,string discriminant,address owner,address resolver,uint96 nonce)");

    address public signingAuthority;

    IMagicDomainRegistrar public registrar;
    IMagicDomainReverseRegistrar public reverseRegistrar;

    mapping(uint96 => bool) public nonceUsed;

    /**
     * @notice address = payment token, PriceInfo is how to get associated costs for payment
     */
    mapping(address => PriceInfo) public tagChangePriceInfo;
    /**
     * @notice Stores which PriceInfo should be used when changing a tag without specifying a payment token
     */
    address public defaultPaymentTokenAddress;

    function initialize(
        IMagicDomainRegistrar _registrar,
        IMagicDomainReverseRegistrar _reverseRegistrar,
        address _signingAuthority
    ) external initializer {
        __Ownable_init();
        __EIP712_init("MagicDomains", "1.0.0");
        registrar = _registrar;
        reverseRegistrar = _reverseRegistrar;
        signingAuthority = _signingAuthority;
    }

    function valid(string memory name) public pure returns (bool) {
        return name.strlen() >= 3;
    }

    function available(string memory name, string memory discriminant) public view override returns (bool) {
        return valid(name) && registrar.available(registrar.tagToId(name, discriminant));
    }

    function register(
        RegisterArgs calldata _registerArgs,
        bytes calldata _authoritySignature
    ) external override {
        require(!nonceUsed[_registerArgs.nonce], "MagicDomainRegistrarController: Signature nonce already used");
        require(bytes(_registerArgs.discriminant).length == 4, "MagicDomainRegistrarController: Invalid discriminant");
        require(_registerArgs.resolver != address(0) && _registerArgs.resolver.isContract(), 
            "MagicDomainRegistrarController: Resolver is EOA");

        address signer = registerArgsToHash(_registerArgs).recover(_authoritySignature);
        if(signer != signingAuthority) {
            revert InvalidSignature();
        }
        nonceUsed[_registerArgs.nonce] = true;

        registrar.register(_registerArgs.name, _registerArgs.discriminant, _registerArgs.owner);
        
        _setReverseRecord(_registerArgs.name, _registerArgs.discriminant, _registerArgs.resolver, msg.sender);
        emit NameRegistered(
            _registerArgs.name,
            _registerArgs.discriminant,
            _registerArgs.owner
        );
    }

    function changeTag(
        RegisterArgs calldata _registerArgs,
        bytes calldata _authoritySignature
    ) external override {
        require(!nonceUsed[_registerArgs.nonce], "MagicDomainRegistrarController: Signature nonce already used");
        require(bytes(_registerArgs.discriminant).length == 4, "MagicDomainRegistrarController: Invalid discriminant");
        require(_registerArgs.resolver != address(0) && _registerArgs.resolver.isContract(), 
            "MagicDomainRegistrarController: Resolver is EOA");

        address signer = registerArgsToHash(_registerArgs).recover(_authoritySignature);
        if(signer != signingAuthority) {
            revert InvalidSignature();
        }
        nonceUsed[_registerArgs.nonce] = true;
        if(defaultPaymentTokenAddress != address(0)) {
            _takePayment(defaultPaymentTokenAddress, _registerArgs.owner);
        }

        registrar.changeName(_registerArgs.name, _registerArgs.discriminant, _registerArgs.owner);
        
        _setReverseRecord(_registerArgs.name, _registerArgs.discriminant, _registerArgs.resolver, msg.sender);
        emit NameRegistered(
            _registerArgs.name,
            _registerArgs.discriminant,
            _registerArgs.owner
        );
    }

    function withdraw() public {
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawTokens(address _paymentToken) public {
        require(IERC20Upgradeable(_paymentToken).transfer(owner(), IERC20Upgradeable(_paymentToken).balanceOf(address(this))),
            "MagicDomainRegistrarController: Withdrawal unsuccessful");
    }

    function setTagChangePriceInfo(address _paymentToken, PriceInfo calldata _priceInfo) external onlyOwner {
        require(_priceInfo.calculatePriceFromFeed == (address(_priceInfo.priceFeed) != address(0)),
            "MagicDomainRegistrarController: Invalid price feed configuration");
        tagChangePriceInfo[_paymentToken] = _priceInfo;
    }

    function setDefaultPaymentTokenAddress(address _paymentToken) external onlyOwner {
        defaultPaymentTokenAddress = _paymentToken;
    }

    function supportsInterface(bytes4 interfaceID)
        external
        pure
        returns (bool)
    {
        return
            interfaceID == type(IERC165Upgradeable).interfaceId ||
            interfaceID == type(IMagicDomainRegistrarController).interfaceId;
    }

    function domainSeparator() public view returns(bytes32) {
        return _domainSeparatorV4();
    }

    function registerArgsToHash(RegisterArgs calldata _registerArgs) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        REGISTERARGS_TYPE_HASH,
                        keccak256(bytes(_registerArgs.name)),
                        keccak256(bytes(_registerArgs.discriminant)),
                        _registerArgs.owner,
                        _registerArgs.resolver,
                        _registerArgs.nonce
                    )
                )
            );
    }

    function calculatePrice(address _paymentToken) public view returns(uint256 price_) {
        PriceInfo memory _priceInfo = tagChangePriceInfo[_paymentToken];
        price_ = _calculatePrice(_priceInfo);
    }

    /* Internal functions */

    function _takePayment(address _paymentToken, address _tagOwner) internal {
        PriceInfo memory _priceInfo = tagChangePriceInfo[_paymentToken];
        require(_priceInfo.enabled, "MagicDomainRegistrarController: Default payment token not enabled");
        uint256 price = _calculatePrice(_priceInfo);

        require(IERC20Upgradeable(_paymentToken).transferFrom(_tagOwner, address(this), price),
            "MagicDomainRegistrarController: Payment unsuccessful");
    }

    function _calculatePrice(PriceInfo memory _priceInfo) public view returns(uint256 price_) {
        if(_priceInfo.calculatePriceFromFeed) {
            (, int256 quotePrice,,,) = _priceInfo.priceFeed.latestRoundData();
            // Unfortunately no way to determine this ahead of time, and likely will never occur, but is a possibility of the oracle
            require(quotePrice >= 0, "MagicDomainRegistrarController: Only spot price feeds are supported.");
            
            // Complex ex: Price is 10 USD and quote price for MAGIC is 1.82 USD, 10 / 1.82 = 5.494505494505495 MAGIC
            //  Because fixed precision is e18, value will be 5494505494505494505 and needs to be converted to payment token decimal
            // NOTE: It is assumed that the PriceInfo.price and price feed's price are in the same decimal unit
            UD60x18 priceFP = ud(_priceInfo.price).div(ud(uint256(quotePrice)));
            // Lastly, we must convert the price into the payment token's decimal amount
            if(_priceInfo.paymentTokenDecimals > 18) {
                // Add digits equal to the difference of fp's 18 decimals and the payment token's decimals
                price_ = priceFP.unwrap() * 10 ** (_priceInfo.paymentTokenDecimals - 18);
            } else {
                // Remove digits equal to the difference of fp's 18 decimals and the payment token's decimals
                price_ = priceFP.unwrap() / 10 ** (18 - _priceInfo.paymentTokenDecimals);
            }
        } else {
            price_ = _priceInfo.price;
        }
    }

    function _setReverseRecord(
        string memory name,
        string memory discriminant,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(name, ".", discriminant, ".magic") // ex: myname#1234 should be: myname.1234.magic
        );
    }
}
