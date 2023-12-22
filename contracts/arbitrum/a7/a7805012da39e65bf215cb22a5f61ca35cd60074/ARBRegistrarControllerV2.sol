//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "./StringUtils.sol";
import {Resolver} from "./Resolver.sol";
import {ReverseRegistrar} from "./ReverseRegistrar.sol";
import {IARBRegistrarController, IPriceOracle} from "./IARBRegistrarController.sol";
import {Auction} from "./Auction.sol";

import {Ownable} from "./Ownable.sol";
import {IERC165} from "./IERC165.sol";
import {Address} from "./Address.sol";

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

error RegistrationNotStart();
error RegistrationEnded();
error RegistrationQuotaReachedLimit();

/**
 * @dev A registrar controller for registering and renewing on testnet.
 */
contract ARBRegistrarControllerV2 is Ownable, IARBRegistrarController, IERC165 {
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;
    uint256 private constant COIN_TYPE_ARB1 = 2147525809;
    uint256 private constant COIN_TYPE_ARB_NOVA = 2147525818;

    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;

    uint256 public immutable preRegistrationStartTime;
    uint256 public immutable preRegistrationEndTime;

    ReverseRegistrar public immutable reverseRegistrar;
    BaseRegistrarImplementation immutable base;
    Auction immutable auction;
    IPriceOracle public immutable prices;


    mapping(bytes32 => uint256) public commitments;
    //users used registration quotas
    mapping(address => uint256) public usedQuota;

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
        IPriceOracle _prices,
        Auction _auction,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge,
        uint256 _preRegistrationStartTime,
        uint256 _preRegistrationEndTime,
        ReverseRegistrar _reverseRegistrar
    ) {
        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        if (_maxCommitmentAge > block.timestamp) {
            revert MaxCommitmentAgeTooHigh();
        }
        require (
            _preRegistrationStartTime < _preRegistrationEndTime,
            "preRegistrationStartTime must be less than preRegistrationEndTime"
        );
        require (
            _preRegistrationStartTime > block.timestamp,
            "preRegistrationStartTime must be greater than current time"
        );

        preRegistrationStartTime = _preRegistrationStartTime;
        preRegistrationEndTime = _preRegistrationEndTime;
        
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        
        base = _base;
        prices = _prices;
        auction = _auction;
        reverseRegistrar = _reverseRegistrar;
    }

    function winnerOrAvailable(
        string memory name,
        address addr
    ) public view returns (bool, uint256) {
        bytes32 label = keccak256(bytes(name));
        if (!base.available(uint256(label))) {
            return (false, 0);
        }
        uint256 tokenID = uint256(label);
        address winner = auction.winnerOf(tokenID);
        if (winner == address(0)) {
            return (true, 0);
        }
        if (winner == addr) {
            return (true, 31556952);
        }
        return (false, 0);
    }

    function rentPrice(
        string memory name,
        uint256 duration
    ) public view override returns (IPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.price(name, base.nameExpires(uint256(label)), duration);
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

    function commit(bytes32 commitment) onlyAfterStart public override {
        if (commitments[commitment] + maxCommitmentAge >= block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        commitments[commitment] = block.timestamp;
    }

    function registerWithConfig (
        string memory name,
        address owner,
        uint256 duration,
        bytes32 secret,
        address resolver,
        bool reverseRecord
    ) public payable onlyAfterStart override {

        (bool isAvaiable, uint256 freeDuration) = winnerOrAvailable(name, msg.sender);
        if (!isAvaiable) {
            revert NameNotAvailable(name);
        }
        //quota will be consumed if the domain is not a bidded domain
        if(isAvaiable && freeDuration == 0) {
            _consumeQuota(msg.sender);
        }

        IPriceOracle.Price memory price = rentPrice(name, duration - freeDuration);
        if (msg.value < price.base + price.premium) {
            revert InsufficientValue();
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
            payable(msg.sender).transfer(
                msg.value - (price.base + price.premium)
            );
        }
    }

    function renew(
        string calldata name,
        uint duration
    ) external payable override {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint256 cost = (price.base + price.premium);
        if (msg.value < cost) {
            revert InsufficientValue();
        }

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        // Refund any extra payment
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit NameRenewed(name, label, cost, expires);
    }

    function withdraw() public {
        payable(owner()).transfer(address(this).balance);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IARBRegistrarController).interfaceId;
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

    function _consumeQuota(address addr) internal {
        uint256 quota = usedQuota[addr];
        uint256 p2Quotas = auction.phase2Quota(addr);
        if (quota >= p2Quotas) {
            revert RegistrationQuotaReachedLimit();
        }
        usedQuota[addr] = quota + 1;
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


    modifier onlyAfterStart() {
        if (block.timestamp < preRegistrationStartTime) {
            revert RegistrationNotStart();
        }
        _;
    }

    modifier onlyBeforeEnd() {
        if (block.timestamp > preRegistrationEndTime) {
            revert RegistrationEnded();
        }
        _;
    }
}

