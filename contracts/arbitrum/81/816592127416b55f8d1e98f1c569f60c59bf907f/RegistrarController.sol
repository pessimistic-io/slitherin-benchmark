//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./ISidPriceOracle.sol";
import "./SidGiftCardLedger.sol";

import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "./StringUtils.sol";
import {Resolver} from "./Resolver.sol";
import {IRegistrarController} from "./IRegistrarController.sol";

import {Ownable} from "./Ownable.sol";
import {IERC165} from "./IERC165.sol";
import {Address} from "./Address.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

import {ReferralInfo} from "./SidStruct.sol";
import {RegInfo} from "./SidStruct.sol";
import {ReferralHub} from "./ReferralHub.sol";
import {ReferralVerifier} from "./ReferralVerifier.sol";
import {ReverseRegistrar} from "./ReverseRegistrar.sol";

error CommitmentTooNew(bytes32 commitment);
error CommitmentTooOld(bytes32 commitment);
error NameNotAvailable(string name);
error DurationTooShort(uint256 duration);
error ResolverRequiredWhenDataSupplied();
error UnexpiredCommitmentExists(bytes32 commitment);
error InsufficientValue();
error Unauthorised(bytes32 node);
error MaxCommitmentAgeTooLow();
error MaxCommitmentAgeTooHigh();
error InvalidOwner(address owner);

/**
 * @dev A registrar controller for registering and renewing on public phase.
 */
contract RegistrarController is
    IRegistrarController,
    Ownable,
    IERC165,
    ReentrancyGuard
{
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;
    uint256 private constant COIN_TYPE_ARB1 = 2147525809;
    uint256 private constant COIN_TYPE_ARB_NOVA = 2147525818;
    BaseRegistrarImplementation immutable base;
    ISidPriceOracle public immutable prices;
    SidGiftCardLedger public immutable giftCardLedger;
    ReferralHub public immutable referralHub;
    ReferralVerifier public immutable referralVerifier;
    ReverseRegistrar public immutable reverseRegistrar;

    //fund controller
    address public treasuryManager;
    uint256 public version;
    string public subfix = ".arb";

    modifier onlyTreasuryManager() {
        require(
            msg.sender == treasuryManager,
            "Only treasury manager can withdraw"
        );
        _;
    }

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );

    constructor(
        BaseRegistrarImplementation _base,
        ISidPriceOracle _prices,
        SidGiftCardLedger _giftCardLedger,
        ReferralHub _referralHub,
        ReferralVerifier _referralVerifier,
        ReverseRegistrar _reverseRegistrar,
        address _treasuryManager,
        uint256 _version
    ) {
        require(_treasuryManager != address(0));
        base = _base;
        prices = _prices;
        giftCardLedger = _giftCardLedger;
        treasuryManager = _treasuryManager;
        referralHub = _referralHub;
        referralVerifier = _referralVerifier;
        reverseRegistrar = _reverseRegistrar;
        version = _version;
    }

    function rentPrice(
        string calldata name,
        uint256 duration
    ) public view returns (ISidPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.domain(name, base.nameExpires(uint256(label)), duration);
    }

    function rentPriceWithPoint(
        string calldata name,
        uint256 duration,
        address registerAddress
    ) public view returns (ISidPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.domainWithPoint(
            name,
            base.nameExpires(uint256(label)),
            duration,
            registerAddress
        );
    }

    function valid(string calldata name) public pure returns (bool) {
        // check unicode rune count, if rune count is >=3, byte length must be >=3.
        if (name.strlen() < 3) {
            return false;
        }
        bytes memory nb = bytes(name);
        // zero width for /u200b /u200c /u200d and U+FEFF
        for (uint256 i; i < nb.length - 2; i++) {
            if (bytes1(nb[i]) == 0xe2 && bytes1(nb[i + 1]) == 0x80) {
                if (
                    bytes1(nb[i + 2]) == 0x8b ||
                    bytes1(nb[i + 2]) == 0x8c ||
                    bytes1(nb[i + 2]) == 0x8d
                ) {
                    return false;
                }
            } else if (bytes1(nb[i]) == 0xef) {
                if (bytes1(nb[i + 1]) == 0xbb && bytes1(nb[i + 2]) == 0xbf)
                    return false;
            }
        }
        return true;
    }

    function available(string calldata name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    // because this function returns fund based on msg.value
    // it MUST be an external function to avoid accidental call that
    // returns incorrect amount, e.g., bulk register.
    function register(
        string calldata name,
        address owner,
        uint duration
    ) external payable {
        uint256 cost = _registerWithConfigAndPoint(
            name,
            RegInfo(owner, duration, address(0), false, false, msg.value),
            ReferralInfo(address(0), bytes32(0), 0, 0, bytes(""))
        );
        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }

        // because this function returns fund based on msg.value
    // it MUST be an external function to avoid accidental call that
    // returns incorrect amount, e.g., bulk register.
    function registerWithConfigAndPoint(string calldata name, address owner, uint duration, address resolver, bool isUsePoints, bool isSetPrimaryName, ReferralInfo memory referralInfo) external payable {
        uint256 cost = _registerWithConfigAndPoint(name, RegInfo(owner, duration, resolver, isUsePoints, isSetPrimaryName, msg.value), referralInfo);
        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }

    function _registerWithConfigAndPoint(
        string calldata name,
        RegInfo memory regInfo,
        ReferralInfo memory referralInfo
    ) internal nonReentrant returns (uint256 cost) {
        ISidPriceOracle.Price memory price;
        if (regInfo.duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(regInfo.duration);
        }
        if (regInfo.isUsePoints) {
            price = rentPriceWithPoint(name, regInfo.duration, msg.sender);
            //deduct points from gift card ledger
            giftCardLedger.deduct(msg.sender, price.usedPoint);
        } else {
            price = rentPrice(name, regInfo.duration);
        }

        if (regInfo.paidFee < price.base + price.premium) {
            revert InsufficientValue();
        }

        if (regInfo.owner == address(0)) {
            revert InvalidOwner(regInfo.owner);
        }

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        // Set this contract as the (temporary) owner, giving it
        // permission to set up the resolver.
        uint256 expires = base.register(
            tokenId,
            address(this),
            regInfo.duration
        );

        // The nodehash of this label
        bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

        // Set the resolver
        base.arbid().setResolver(nodehash, regInfo.resolver);

        // Configure the resolver with Arbitrum One and Arbitrum Nova
        if (regInfo.owner != address(0)) {
            Resolver(regInfo.resolver).setAddr(
                nodehash,
                COIN_TYPE_ARB1,
                regInfo.owner
            );
            Resolver(regInfo.resolver).setAddr(
                nodehash,
                COIN_TYPE_ARB_NOVA,
                regInfo.owner
            );
        }

        // Now transfer full ownership to the expeceted owner
        base.reclaim(tokenId, regInfo.owner);
        base.transferFrom(address(this), regInfo.owner, tokenId);

        emit NameRegistered(
            name,
            keccak256(bytes(name)),
            regInfo.owner,
            price.base,
            price.premium,
            expires
        );

        cost = price.base + price.premium;
        if (referralInfo.referrerAddress != address(0)) {
            cost = _handleReferral(
                cost,
                referralInfo.referrerAddress,
                referralInfo.referrerNodehash,
                referralInfo.referralAmount,
                referralInfo.signedAt,
                referralInfo.signature
            );
        }
        if (regInfo.isSetPrimaryName) {
            _setReverseRecord(name, regInfo.resolver, regInfo.owner);
        }

        return cost;
    }

    function renew(string calldata name, uint duration) external payable {
        uint256 cost = _renewWithPoint(name, duration, false, msg.value);
        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }

    // because this function returns fund based on msg.value
    // it MUST be an external function to avoid accidental call that
    // returns incorrect amount, e.g., bulk register.
    function renewWithPoint(
        string calldata name,
        uint duration,
        bool isUsePoints
    ) external payable {
        uint256 cost = _renewWithPoint(name, duration, isUsePoints, msg.value);
        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }

    function _renewWithPoint(
        string calldata name,
        uint duration,
        bool isUsePoints,
        uint256 paid
    ) internal nonReentrant returns (uint256 cost) {
        ISidPriceOracle.Price memory price;
        if (isUsePoints) {
            price = rentPriceWithPoint(name, duration, msg.sender);
            //deduct points from gift card ledger
            giftCardLedger.deduct(msg.sender, price.usedPoint);
        } else {
            price = rentPrice(name, duration);
        }
        cost = (price.base + price.premium);
        require(paid >= cost);
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);
        emit NameRenewed(name, label, cost, expires);
        return cost;
    }

    function withdraw() public onlyTreasuryManager nonReentrant {
        (bool sent, ) = treasuryManager.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function setTreasuryManager(address _treasuryManager) public onlyOwner {
        require(_treasuryManager != address(0));
        treasuryManager = _treasuryManager;
        emit NewTreasuryManager(_treasuryManager);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IRegistrarController).interfaceId;
    }

    function bulkRentPrice(string[] calldata names, uint256 duration) public view returns (uint256 total) {
        for (uint256 i = 0; i < names.length; i++) {
            ISidPriceOracle.Price memory price = rentPrice(names[i], duration);
            total += (price.base + price.premium);
        }
    }

    function bulkRegister(string[] calldata names, address owner, uint duration, address resolver, bool isUseGiftCard, bool isSetPrimaryName, ReferralInfo memory referralInfo) external payable {
        uint256 unspent = msg.value;
        for (uint256 i = 0; i < names.length; i++) {
            uint256 cost = _registerWithConfigAndPoint(names[i], RegInfo(owner, duration, resolver, isUseGiftCard, isSetPrimaryName, unspent), referralInfo);
            unspent -= cost;
        }
        // Refund any extra payment
        if (unspent > 0) {
            (bool sent, ) = msg.sender.call{value: unspent}("");
            require(sent, "Failed to send Ether");
        }
    }

    function bulkRenew(string[] calldata names, uint duration, bool isUsePoints) external payable {
        uint256 unspent = msg.value;
        for (uint256 i = 0; i < names.length; i++) {
            uint256 cost = _renewWithPoint(names[i], duration, isUsePoints, unspent);
            unspent -= cost;
        }
        // Refund any extra payment
        if (unspent > 0) {
            (bool sent, ) = msg.sender.call{value: unspent}("");
            require(sent, "Failed to send Ether");
        }
    }

    function _handleReferral(
        uint cost,
        address referrerAddress,
        bytes32 referrerNodehash,
        uint256 referralAmount,
        uint256 signedAt,
        bytes memory signature
    ) internal returns (uint) {
        require(
            referralVerifier.verifyReferral(
                referrerAddress,
                referrerNodehash,
                referralAmount,
                signedAt,
                signature
            ),
            "Invalid referral signature"
        );
        uint256 referrerFee = 0;
        uint256 refereeFee = 0;
        if (referralHub.isPartner(referrerNodehash)) {
            (referrerFee, refereeFee) = referralHub.getReferralCommisionFee(
                cost,
                referrerNodehash
            );
        } else {
            (referrerFee, refereeFee) = referralVerifier
                .getReferralCommisionFee(cost, referralAmount);
        }
        referralHub.addNewReferralRecord(referrerNodehash);
        if (referrerFee > 0) {
            referralHub.deposit{value: referrerFee}(referrerAddress);
        }
        return cost - refereeFee;
    }

    function _setReverseRecord(
        string memory name,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(name, subfix)
        );
    }
}

