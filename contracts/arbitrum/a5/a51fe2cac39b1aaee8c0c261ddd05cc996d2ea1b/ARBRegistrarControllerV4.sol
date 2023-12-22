//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./ISidPriceOracle.sol";
import "./SidGiftCardLedger.sol";

import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "./StringUtils.sol";
import {Resolver} from "./Resolver.sol";
import {ReverseRegistrar} from "./ReverseRegistrar.sol";
import {IARBRegistrarControllerV2, ISidPriceOracle} from "./IARBRegistrarControllerV2.sol";

import {Ownable} from "./Ownable.sol";
import {IERC165} from "./IERC165.sol";
import {Address} from "./Address.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

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
contract ARBRegistrarControllerV4 is
    Ownable,
    IARBRegistrarControllerV2,
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
    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;
    ReverseRegistrar public immutable reverseRegistrar;
    SidGiftCardLedger public immutable giftCardLedger;

    mapping(bytes32 => uint256) public commitments;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );
    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );

    constructor(
        BaseRegistrarImplementation _base,
        ISidPriceOracle _prices,
        SidGiftCardLedger _giftCardLedger,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge,
        ReverseRegistrar _reverseRegistrar
    ) {
        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        if (_maxCommitmentAge > block.timestamp) {
            revert MaxCommitmentAgeTooHigh();
        }

        base = _base;
        prices = _prices;
        giftCardLedger = _giftCardLedger;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        reverseRegistrar = _reverseRegistrar;
    }

    function rentPrice(
        string memory name,
        uint256 duration
    ) public view override returns (ISidPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.domain(name, base.nameExpires(uint256(label)), duration);
    }

    function rentPrice(
        string memory name,
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

    function valid(string memory name) public pure returns (bool) {
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

    function available(string memory name) public view override returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret
    ) public pure override returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(label, owner, secret));
    }

    function commit(bytes32 commitment) public override {
        if (commitments[commitment] + maxCommitmentAge >= block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        commitments[commitment] = block.timestamp;
    }

    function registerWithConfigAndPoint(
        string memory name,
        address owner,
        uint duration,
        bytes32 secret,
        address resolver,
        bool reverseRecord,
        bool isUsePoints
    ) public payable override nonReentrant {
        ISidPriceOracle.Price memory price;
        if (isUsePoints) {
            price = rentPrice(name, duration, owner);
            //deduct points from gift card ledger
            giftCardLedger.deduct(owner, price.usedPoint);
        } else {
            price = rentPrice(name, duration);
        }

        if (msg.value < price.base + price.premium) {
            revert InsufficientValue();
        }

        if (owner == address(0)) {
            revert InvalidOwner(owner);
        }

        _consumeCommitment(name, duration, makeCommitment(name, owner, secret));

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        // Set this contract as the (temporary) owner, giving it
        // permission to set up the resolver.
        uint256 expires = base.register(tokenId, address(this), duration);

        // The nodehash of this label
        bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

        // Set the resolver
        base.arbid().setResolver(nodehash, resolver);

        // Configure the resolver with Arbitrum One and Arbitrum Nova
        if (owner != address(0)) {
            Resolver(resolver).setAddr(nodehash, COIN_TYPE_ARB1, owner);
            Resolver(resolver).setAddr(nodehash, COIN_TYPE_ARB_NOVA, owner);
        }

        // Now transfer full ownership to the expeceted owner
        base.reclaim(tokenId, owner);
        base.transferFrom(address(this), owner, tokenId);

        if (reverseRecord) {
            _setReverseRecord(name, resolver, owner);
        }

        emit NameRegistered(
            name,
            keccak256(bytes(name)),
            owner,
            price.base,
            price.premium,
            expires
        );

        if (msg.value > (price.base + price.premium)) {
            (bool sent, ) = msg.sender.call{
                value: msg.value - (price.base + price.premium)
            }("");
            require(sent, "Failed to send Ether");
        }
    }

    function registerWithConfig(
        string calldata name,
        address owner,
        uint256 duration,
        bytes32 secret,
        address resolver,
        bool reverseRecord
    ) public payable override {
        registerWithConfigAndPoint(
            name,
            owner,
            duration,
            secret,
            resolver,
            reverseRecord,
            false
        );
    }

    function renew(
        string calldata name,
        uint duration
    ) external payable override nonReentrant {
        renewWithPoint(name, duration, false);
    }

    function renewWithPoint(
        string calldata name,
        uint duration,
        bool isUsePoints
    ) public payable nonReentrant {
        ISidPriceOracle.Price memory price;
        if (isUsePoints) {
            price = rentPrice(name, duration, msg.sender);
            //deduct points from gift card ledger
            giftCardLedger.deduct(msg.sender, price.usedPoint);
        } else {
            price = rentPrice(name, duration);
        }
        uint256 cost = (price.base + price.premium);
        require(msg.value >= cost);
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }

        emit NameRenewed(name, label, cost, expires);
    }

    function withdraw() public onlyOwner nonReentrant {
        (bool sent, ) = owner().call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IARBRegistrarControllerV2).interfaceId;
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory name,
        uint256 duration,
        bytes32 commitment
    ) internal {
        // Require an old enough commitment.
        if (commitments[commitment] + minCommitmentAge > block.timestamp) {
            revert CommitmentTooNew(commitment);
        }

        // If the commitment is too old, or the name is registered, stop
        if (commitments[commitment] + maxCommitmentAge <= block.timestamp) {
            revert CommitmentTooOld(commitment);
        }
        if (!available(name)) {
            revert NameNotAvailable(name);
        }

        delete (commitments[commitment]);

        if (duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(duration);
        }
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
            string.concat(name, ".arb")
        );
    }
}

