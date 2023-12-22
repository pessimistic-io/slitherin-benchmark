// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Address } from "./Address.sol";
import { Initializable } from "./lib_Initializable.sol";

import { AvoMultiSafe } from "./AvoMultiSafe.sol";
import { IAvoWalletV3 } from "./IAvoWalletV3.sol";
import { IAvoMultisigV3 } from "./IAvoMultisigV3.sol";
import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";
import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoForwarder } from "./IAvoForwarder.sol";

// --------------------------- DEVELOPER NOTES -----------------------------------------
// @dev To deploy a new version of AvoSafe (proxy), the new factory contract must be deployed
// and AvoFactoryProxy upgraded to that new contract (to update the cached bytecode).
// -------------------------------------------------------------------------------------

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoFactory v3.0.0
/// @notice Deploys Avocado smart wallet contracts at deterministic addresses using Create2.
///
/// Upgradeable through AvoFactoryProxy
interface AvoFactory_V3 {

}

abstract contract AvoFactoryErrors {
    /// @notice thrown when trying to deploy an AvoSafe for a smart contract
    error AvoFactory__NotEOA();

    /// @notice thrown when a caller is not authorized to execute a certain action
    error AvoFactory__Unauthorized();

    /// @notice thrown when a method is called with invalid params (e.g. zero address)
    error AvoFactory__InvalidParams();
}

abstract contract AvoFactoryConstants is AvoFactoryErrors, IAvoFactory {
    /// @notice hardcoded AvoSafe creation code.
    //
    // Hardcoding this allows us to enable the optimizer without affecting the bytecode of the AvoSafe proxy,
    // which would break the deterministic address of previous versions.
    // in next version, also hardcode the creation code for the avoMultiSafe
    bytes public constant avoSafeCreationCode =
        hex"608060405234801561001057600080fd5b506000803373ffffffffffffffffffffffffffffffffffffffff166040518060400160405280600481526020017f8e7daf690000000000000000000000000000000000000000000000000000000081525060405161006e91906101a5565b6000604051808303816000865af19150503d80600081146100ab576040519150601f19603f3d011682016040523d82523d6000602084013e6100b0565b606091505b50915091506000602082015190508215806100e2575060008173ffffffffffffffffffffffffffffffffffffffff163b145b156100ec57600080fd5b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505050506101bc565b600081519050919050565b600081905092915050565b60005b8381101561016857808201518184015260208101905061014d565b60008484015250505050565b600061017f82610134565b610189818561013f565b935061019981856020860161014a565b80840191505092915050565b60006101b18284610174565b915081905092915050565b60aa806101ca6000396000f3fe608060405273ffffffffffffffffffffffffffffffffffffffff600054167f87e9052a0000000000000000000000000000000000000000000000000000000060003503604f578060005260206000f35b3660008037600080366000845af43d6000803e8060008114606f573d6000f35b3d6000fdfea26469706673582212206b87e9571aaea9ed523b568c544f1e27605a9e60767f9b6c9efbab3ad8293ea864736f6c63430008110033";

    /// @notice cached AvoSafe bytecode hash to optimize gas usage
    bytes32 public constant avoSafeBytecode = keccak256(abi.encodePacked(avoSafeCreationCode));

    /// @notice cached AvoSafeMultsig bytecode hash to optimize gas usage
    bytes32 public constant avoMultiSafeBytecode = keccak256(abi.encodePacked(type(AvoMultiSafe).creationCode));

    /// @notice  registry holding the valid versions (addresses) for Avocado smart wallet implementation contracts.
    ///          The registry is used to verify a valid version before setting a new `avoWalletImpl` / `avoMultisigImpl`
    ///          as default for new deployments.
    IAvoVersionsRegistry public immutable avoVersionsRegistry;

    constructor(IAvoVersionsRegistry avoVersionsRegistry_) {
        avoVersionsRegistry = avoVersionsRegistry_;

        if (avoSafeBytecode != 0x9aa119706de4bc0b1d341ea3b741a89ce1da096034c271d93473502675bb2c11) {
            revert AvoFactory__InvalidParams();
        }
        // @dev in next version, add the same check for (hardcoded) avoMultiSafeBytecode
    }
}

abstract contract AvoFactoryVariables is AvoFactoryConstants, Initializable {
    // @dev Before variables here are vars from Initializable:
    // uint8 private _initialized;
    // bool private _initializing;

    /// @notice Avo wallet logic contract address that new AvoSafe deployments point to.
    ///         Modifiable only by `avoVersionsRegistry`.
    address public avoWalletImpl;

    // 10 bytes empty

    // ----------------------- slot 1 ---------------------------

    /// @notice AvoMultisig logic contract address that new AvoMultiSafe deployments point to.
    ///         Modifiable only by `avoVersionsRegistry`.
    address public avoMultisigImpl;
}

abstract contract AvoFactoryEvents {
    /// @notice Emitted when a new AvoSafe has been deployed
    event AvoSafeDeployed(address indexed owner, address indexed avoSafe);

    /// @notice Emitted when a new AvoSafe has been deployed with a non-default version
    event AvoSafeDeployedWithVersion(address indexed owner, address indexed avoSafe, address indexed version);

    /// @notice Emitted when a new AvoMultiSafe has been deployed
    event AvoMultiSafeDeployed(address indexed owner, address indexed avoMultiSafe);

    /// @notice Emitted when a new AvoMultiSafe has been deployed with a non-default version
    event AvoMultiSafeDeployedWithVersion(address indexed owner, address indexed avoMultiSafe, address indexed version);
}

abstract contract AvoForwarderCore is AvoFactoryErrors, AvoFactoryConstants, AvoFactoryVariables, AvoFactoryEvents {
    constructor(IAvoVersionsRegistry avoVersionsRegistry_) AvoFactoryConstants(avoVersionsRegistry_) {
        if (address(avoVersionsRegistry_) == address(0)) {
            revert AvoFactory__InvalidParams();
        }

        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }
}

contract AvoFactory is AvoForwarderCore {
    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    /// @dev reverts if `owner_` is a contract
    modifier onlyEOA(address owner_) {
        if (Address.isContract(owner_)) {
            revert AvoFactory__NotEOA();
        }
        _;
    }

    /// @dev reverts if `msg.sender` is not `avoVersionsRegistry`
    modifier onlyRegistry() {
        if (msg.sender != address(avoVersionsRegistry)) {
            revert AvoFactory__Unauthorized();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice constructor sets the immutable `avoVersionsRegistry` address
    constructor(IAvoVersionsRegistry avoVersionsRegistry_) AvoForwarderCore(avoVersionsRegistry_) {}

    /// @notice initializes the contract
    function initialize() public initializer {}

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    /// @inheritdoc IAvoFactory
    function isAvoSafe(address avoSafe_) external view returns (bool) {
        if (avoSafe_ == address(0)) {
            return false;
        }
        if (Address.isContract(avoSafe_) == false) {
            // can not recognize isAvoSafe when not yet deployed
            return false;
        }

        // get the owner from the Avocado smart wallet
        try IAvoWalletV3(avoSafe_).owner() returns (address owner_) {
            // compute the AvoSafe address for that owner
            address computedAddress_ = computeAddress(owner_);
            if (computedAddress_ == avoSafe_) {
                // computed address for owner is an avoSafe because it matches a computed address,
                // which includes the address of this contract itself so it also guarantees the AvoSafe
                // was deployed by the AvoFactory.
                return true;
            } else {
                // if it is not a computed address match for the AvoSafe, try for the Multisig too
                computedAddress_ = computeAddressMultisig(owner_);
                return computedAddress_ == avoSafe_;
            }
        } catch {
            // if fetching owner doesn't work, it can not be an Avocado smart wallet
            return false;
        }
    }

    /// @inheritdoc IAvoFactory
    function deploy(address owner_) external onlyEOA(owner_) returns (address deployedAvoSafe_) {
        // deploy AvoSafe deterministically using low level CREATE2 opcode to use hardcoded AvoSafe bytecode
        bytes32 salt_ = _getSalt(owner_);
        bytes memory byteCode_ = avoSafeCreationCode;
        assembly {
            deployedAvoSafe_ := create2(0, add(byteCode_, 0x20), mload(byteCode_), salt_)
        }

        // initialize AvoWallet through proxy with IAvoWallet interface
        IAvoWalletV3(deployedAvoSafe_).initialize(owner_);

        emit AvoSafeDeployed(owner_, deployedAvoSafe_);
    }

    /// @inheritdoc IAvoFactory
    function deployWithVersion(
        address owner_,
        address avoWalletVersion_
    ) external onlyEOA(owner_) returns (address deployedAvoSafe_) {
        avoVersionsRegistry.requireValidAvoWalletVersion(avoWalletVersion_);

        // deploy AvoSafe deterministically using low level CREATE2 opcode to use hardcoded AvoSafe bytecode
        bytes32 salt_ = _getSalt(owner_);
        bytes memory byteCode_ = avoSafeCreationCode;
        assembly {
            deployedAvoSafe_ := create2(0, add(byteCode_, 0x20), mload(byteCode_), salt_)
        }

        // initialize AvoWallet through proxy with IAvoWallet interface
        IAvoWalletV3(deployedAvoSafe_).initializeWithVersion(owner_, avoWalletVersion_);

        emit AvoSafeDeployedWithVersion(owner_, deployedAvoSafe_, avoWalletVersion_);
    }

    /// @inheritdoc IAvoFactory
    function deployMultisig(address owner_) external onlyEOA(owner_) returns (address deployedAvoMultiSafe_) {
        // deploy AvoMultiSafe deterministically using CREATE2 opcode (through specifying salt)
        // Note: because `AvoMultiSafe` bytecode differs from `AvoSafe` bytecode, the deterministic address
        // will be different from the deployed AvoSafes through `deploy` / `deployWithVersion`
        deployedAvoMultiSafe_ = address(new AvoMultiSafe{ salt: _getSaltMultisig(owner_) }());

        // initialize AvoMultisig through proxy with IAvoMultisig interface
        IAvoMultisigV3(deployedAvoMultiSafe_).initialize(owner_);

        emit AvoMultiSafeDeployed(owner_, deployedAvoMultiSafe_);
    }

    /// @inheritdoc IAvoFactory
    function deployMultisigWithVersion(
        address owner_,
        address avoMultisigVersion_
    ) external onlyEOA(owner_) returns (address deployedAvoMultiSafe_) {
        avoVersionsRegistry.requireValidAvoMultisigVersion(avoMultisigVersion_);

        // deploy AvoMultiSafe deterministically using CREATE2 opcode (through specifying salt)
        // Note: because `AvoMultiSafe` bytecode differs from `AvoSafe` bytecode, the deterministic address
        // will be different from the deployed AvoSafes through `deploy()` / `deployWithVersion`
        deployedAvoMultiSafe_ = address(new AvoMultiSafe{ salt: _getSaltMultisig(owner_) }());

        // initialize AvoMultisig through proxy with IAvoMultisig interface
        IAvoMultisigV3(deployedAvoMultiSafe_).initializeWithVersion(owner_, avoMultisigVersion_);

        emit AvoMultiSafeDeployedWithVersion(owner_, deployedAvoMultiSafe_, avoMultisigVersion_);
    }

    /// @inheritdoc IAvoFactory
    function computeAddress(address owner_) public view returns (address computedAddress_) {
        if (Address.isContract(owner_)) {
            // owner of a AvoSafe must be an EOA, if it's a contract return zero address
            return address(0);
        }

        // replicate Create2 address determination logic
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _getSalt(owner_), avoSafeBytecode));

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @inheritdoc IAvoFactory
    function computeAddressMultisig(address owner_) public view returns (address computedAddress_) {
        if (Address.isContract(owner_)) {
            // owner of a AvoMultiSafe must be an EOA, if it's a contract return zero address
            return address(0);
        }

        // replicate Create2 address determination logic
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), _getSaltMultisig(owner_), avoMultiSafeBytecode)
        );

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /***********************************|
    |            ONLY  REGISTRY         |
    |__________________________________*/

    /// @inheritdoc IAvoFactory
    function setAvoWalletImpl(address avoWalletImpl_) external onlyRegistry {
        // do not use `registry.requireValidAvoWalletVersion()` because sender is registry anyway
        avoWalletImpl = avoWalletImpl_;
    }

    /// @inheritdoc IAvoFactory
    function setAvoMultisigImpl(address avoMultisigImpl_) external onlyRegistry {
        // do not `registry.requireValidAvoMultisigVersion()` because sender is registry anyway
        avoMultisigImpl = avoMultisigImpl_;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev            gets the salt used for deterministic deployment for `owner_`
    /// @param owner_   AvoSafe owner
    /// @return         the bytes32 (keccak256) salt
    function _getSalt(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner_));
    }

    /// @dev            gets the salt used for deterministic Multisig deployment for `owner_`
    /// @param owner_   AvoMultiSafe owner
    /// @return         the bytes32 (keccak256) salt
    function _getSaltMultisig(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner_));
    }
}

