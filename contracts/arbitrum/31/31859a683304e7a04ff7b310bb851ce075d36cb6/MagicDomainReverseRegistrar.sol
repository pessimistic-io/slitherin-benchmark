// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {AddressUpgradeable} from "./AddressUpgradeable.sol";

import {ControllableAbs} from "./ControllableAbs.sol";

import {IMagicDomainRegistry} from "./IMagicDomainRegistry.sol";
import {INameResolver} from "./INameResolver.sol";
import {IMagicDomainReverseRegistrar} from "./IMagicDomainReverseRegistrar.sol";

contract MagicDomainReverseRegistrar is ControllableAbs, IMagicDomainReverseRegistrar {
    // Hex representation of 0123456789abcdef used for character lookup
    bytes32 internal constant ALPHANUMERIC_HEX =
        0x3031323334353637383961626364656600000000000000000000000000000000;
    // namehash('addr.reverse')
    bytes32 internal constant ADDR_REVERSE_NODE =
        0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    // Role required to perform sensitive operations
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    IMagicDomainRegistry public magicDomains;
    INameResolver public defaultResolver;

    /**
     * @dev Initializer for the contract
     * @param _magicDomains The address of the MagicDomainRegistry contract.
     */
    function initialize(IMagicDomainRegistry _magicDomains) initializer public {
        __Controllable_init();
        magicDomains = _magicDomains;

        // Assign ownership of the reverse record to our deployer
        MagicDomainReverseRegistrar oldRegistrar = MagicDomainReverseRegistrar(
            _magicDomains.owner(ADDR_REVERSE_NODE)
        );
        if (address(oldRegistrar) != address(0x0)) {
            oldRegistrar.claim(msg.sender);
        }
    }

    function setDefaultResolver(address resolver) public override onlyController {
        require(
            resolver != address(0),
            "ReverseRegistrar: Resolver address must not be 0"
        );
        defaultResolver = INameResolver(resolver);
        emit DefaultResolverChanged(resolver);
    }

    /**
     * @dev Transfers ownership of the reverse IMagicDomainRegistry record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in IMagicDomainRegistry.
     * @return The IMagicDomainRegistry node hash of the reverse record.
     */
    function claim(address owner) public override returns (bytes32) {
        return claimForAddr(msg.sender, owner, address(defaultResolver));
    }

    /**
     * @dev Transfers ownership of the reverse IMagicDomainRegistry record associated with the
     *      calling account.
     * @param addr The reverse record to set
     * @param owner The address to set as the owner of the reverse record in IMagicDomainRegistry.
     * @param resolver The resolver of the reverse node
     * @return The IMagicDomainRegistry node hash of the reverse record.
     */
    function claimForAddr(
        address addr,
        address owner,
        address resolver
    ) public override authorized(addr) returns (bytes32) {
        bytes32 labelHash = sha3HexAddress(addr);
        bytes32 reverseNode = keccak256(
            abi.encodePacked(ADDR_REVERSE_NODE, labelHash)
        );
        emit ReverseClaimed(addr, reverseNode);
        magicDomains.setSubnodeRecord(ADDR_REVERSE_NODE, labelHash, owner, resolver, 0);
        return reverseNode;
    }

    /**
     * @dev Transfers ownership of the reverse IMagicDomainRegistry record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in IMagicDomainRegistry.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The IMagicDomainRegistry node hash of the reverse record.
     */
    function claimWithResolver(address owner, address resolver)
        public
        override
        returns (bytes32)
    {
        return claimForAddr(msg.sender, owner, resolver);
    }

    /**
     * @dev Sets the `name()` record for the reverse IMagicDomainRegistry record associated with
     * the calling account. First updates the resolver to the default reverse
     * resolver if necessary.
     * @param name The name to set for this address.
     * @return The IMagicDomainRegistry node hash of the reverse record.
     */
    function setName(string memory name) public override returns (bytes32) {
        return
            setNameForAddr(
                msg.sender,
                msg.sender,
                address(defaultResolver),
                name
            );
    }

    /**
     * @dev Sets the `name()` record for the reverse IMagicDomainRegistry record associated with
     * the account provided. Updates the resolver to a designated resolver
     * Only callable by controllers and authorized users
     * @param addr The reverse record to set
     * @param owner The owner of the reverse node
     * @param resolver The resolver of the reverse node
     * @param name The name to set for this address.
     * @return The IMagicDomainRegistry node hash of the reverse record.
     */
    function setNameForAddr(
        address addr,
        address owner,
        address resolver,
        string memory name
    ) public override returns (bytes32) {
        bytes32 _node = claimForAddr(addr, owner, resolver);
        require(ERC165Upgradeable(resolver).supportsInterface(type(INameResolver).interfaceId),
            "MagicDomainsReverseRegistrar: invalid resolver");
        INameResolver(resolver).setName(_node, name);
        return _node;
    }

    /**
     * @dev Returns the node hash for a given account's reverse records.
     * @param addr The address to hash
     * @return The IMagicDomainRegistry node hash.
     */
    function node(address addr) public pure override returns (bytes32) {
        return keccak256(
            abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr))
        );
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Ethereum address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        assembly {
            for {
                let i := 40
            } gt(i, 0) {

            } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), ALPHANUMERIC_HEX))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), ALPHANUMERIC_HEX))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }

    /**
     * If the address is a contract, ensure that the sender owns the contract. 
     */
    function ownsContract(address addr) internal view returns (bool) {
        if(!AddressUpgradeable.isContract(addr)) {
            return false;
        }
        try OwnableUpgradeable(addr).owner() returns (address owner) {
            return owner == msg.sender;
        } catch {
            return false;
        }
    }

    modifier authorized(address addr) {
        require(
            addr == msg.sender ||
                controllers[msg.sender] ||
                magicDomains.isApprovedForAll(addr, msg.sender) ||
                ownsContract(addr),
            "ReverseRegistrar: Caller is not a controller or authorized by address or the address itself"
        );
        _;
    }
}
