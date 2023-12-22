// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Address } from "./Address.sol";
import { Initializable } from "./Initializable.sol";
import { Create2Upgradeable } from "./Create2Upgradeable.sol";

import { AvoSafe } from "./AvoSafe.sol";
import { IAvoWallet } from "./IAvoWallet.sol";
import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoForwarder } from "./IAvoForwarder.sol";

/// @title      AvoFactory
/// @notice     Deploys AvoSafe contracts at deterministic addresses using Create2
/// @dev        Upgradeable through AvoFactoryProxy
///             To deploy a new version of AvoSafe, the new factory contract must be deployed
///             and AvoFactoryProxy upgraded to that new contract
contract AvoFactory is IAvoFactory, Initializable {
    /// @dev cached AvoSafe Bytecode to optimize gas usage
    bytes32 public constant avoSafeBytecode = keccak256(abi.encodePacked(type(AvoSafe).creationCode));

    /***********************************|
    |                ERRORS             |
    |__________________________________*/

    error AvoFactory__NotEOA();
    error AvoFactory__Unauthorized();
    error AvoFactory__InvalidParams();

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice  registry holding the valid versions (addresses) for AvoWallet implementation contracts
    ///          The registry is used to verify a valid version before setting a new avoWalletImpl
    ///          as default for new deployments
    IAvoVersionsRegistry public immutable avoVersionsRegistry;

    /// @notice Avo wallet logic contract address that new AvoSafe deployments point to
    ///         modifiable by AvoVersionsRegistry
    address public avoWalletImpl;

    /***********************************|
    |               EVENTS              |
    |__________________________________*/

    /// @notice Emitted when a new AvoSafe has been deployed
    event AvoSafeDeployed(address indexed owner, address indexed avoSafe);

    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    /// @notice reverts if owner_ is a contract
    modifier onlyEOA(address owner_) {
        if (Address.isContract(owner_)) {
            revert AvoFactory__NotEOA();
        }
        _;
    }

    /// @notice reverts if msg.sender is not AvoVersionsRegistry
    modifier onlyRegistry() {
        if (msg.sender != address(avoVersionsRegistry)) {
            revert AvoFactory__Unauthorized();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice constructor sets the immutable avoVersionsRegistry address
    /// @param  avoVersionsRegistry_ address of AvoVersionsRegistry
    /// @dev    setting the avoVersionsRegistry on the logic contract at deployment is ok because the
    ///         AvoVersionsRegistry is upgradeable so the address set here is the proxy address
    ///         which really shouldn't change. Even if it should change then worst case
    ///         a new AvoFactory logic contract has to be deployed pointing to a new registry
    constructor(IAvoVersionsRegistry avoVersionsRegistry_) {
        if (address(avoVersionsRegistry_) == address(0)) {
            revert AvoFactory__InvalidParams();
        }
        avoVersionsRegistry = avoVersionsRegistry_;

        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @notice initializes the contract
    function initialize() public initializer {}

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    /// @inheritdoc IAvoFactory
    function deploy(address owner_) external onlyEOA(owner_) returns (address) {
        return _deployAvoSafeDeterministic(owner_);
    }

    /// @inheritdoc IAvoFactory
    function computeAddress(address owner_) public view returns (address) {
        if (Address.isContract(owner_)) {
            // owner of a AvoSafe must be an EOA, if it's a contract return zero address
            return address(0);
        }
        return _computeAvoSafeAddress(owner_);
    }

    /***********************************|
    |            ONLY  REGISTRY         |
    |__________________________________*/

    /// @inheritdoc IAvoFactory
    function setAvoWalletImpl(address avoWalletImpl_) external onlyRegistry {
        // do not requireValidAvoWalletVersion because sender is registry anyway
        avoWalletImpl = avoWalletImpl_;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev            computes the deterministic contract address for a AvoSafe deployment for owner_
    /// @param  owner_  AvoSafe owner
    /// @return         the computed contract address
    function _computeAvoSafeAddress(address owner_) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _getSalt(owner_), avoSafeBytecode));

        // cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /// @dev                        deploys a AvoSafe deterministically for owner_
    /// @param owner_               AvoSafe owner
    /// @return deployedAvoSafe_    the deployed contract address
    function _deployAvoSafeDeterministic(address owner_) internal returns (address deployedAvoSafe_) {
        // deploy AvoSafe using CREATE2 opcode (through specifying salt)
        deployedAvoSafe_ = address(new AvoSafe{ salt: _getSalt(owner_) }());

        // initialize AvoWallet through proxy with IAvoWallet interface
        IAvoWallet(deployedAvoSafe_).initialize(owner_);

        emit AvoSafeDeployed(owner_, deployedAvoSafe_);
    }

    /// @dev            gets the salt used for deterministic deployment for owner_
    /// @param owner_   AvoSafe owner
    /// @return         the bytes32 (keccak256) salt
    function _getSalt(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner_));
    }
}

