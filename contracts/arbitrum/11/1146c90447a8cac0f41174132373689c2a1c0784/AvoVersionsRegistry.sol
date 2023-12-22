// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Initializable } from "./lib_Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoVersionsRegistry, IAvoFeeCollector } from "./IAvoVersionsRegistry.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoVersionsRegistry v3.0.0
/// @notice Registry for various config data and general actions for Avocado contracts:
/// - holds lists of valid versions for AvoWallet, AvoMultisig & AvoForwarder
/// - handles fees for `castAuthorized()` calls
///
/// Upgradeable through AvoVersionsRegistryProxy
interface AvoVersionsRegistry_V3 {

}

abstract contract AvoVersionsRegistryConstants is IAvoVersionsRegistry {
    /// @notice AvoFactory where new versions get registered automatically as default version on `registerAvoVersion()`
    IAvoFactory public immutable avoFactory;

    constructor(IAvoFactory avoFactory_) {
        avoFactory = avoFactory_;
    }
}

abstract contract AvoVersionsRegistryVariables is IAvoVersionsRegistry, Initializable, OwnableUpgradeable {
    // @dev variables here start at storage slot 101, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - OwnableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // address private _owner; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)

    // ---------------- slot 101 -----------------

    /// @notice fee config for `calcFee()`. Configurable by owner.
    //
    // @dev address avoFactory used to be at this storage slot until incl. v2.0. Storage slot repurposed with upgrade v3.0
    FeeConfig public feeConfig;

    // ---------------- slot 102 -----------------

    /// @notice mapping to store allowed AvoWallet versions. Modifiable by owner.
    mapping(address => bool) public avoWalletVersions;

    // ---------------- slot 103 -----------------

    /// @notice mapping to store allowed AvoForwarder versions. Modifiable by owner.
    mapping(address => bool) public avoForwarderVersions;

    // ---------------- slot 104 -----------------

    /// @notice mapping to store allowed AvoMultisig versions. Modifiable by owner.
    mapping(address => bool) public avoMultisigVersions;
}

abstract contract AvoVersionsRegistryErrors {
    /// @notice thrown for `requireVersion()` methods
    error AvoVersionsRegistry__InvalidVersion();

    /// @notice thrown when a requested fee mode is not implemented
    error AvoVersionsRegistry__FeeModeNotImplemented(uint8 mode);

    /// @notice thrown when a method is called with invalid params, e.g. the zero address
    error AvoVersionsRegistry__InvalidParams();
}

abstract contract AvoVersionsRegistryEvents is IAvoVersionsRegistry {
    /// @notice emitted when the status for a certain AvoWallet version is updated
    event SetAvoWalletVersion(address indexed avoWalletVersion, bool indexed allowed, bool indexed setDefault);

    /// @notice emitted when the status for a certain AvoMultsig version is updated
    event SetAvoMultisigVersion(address indexed avoMultisigVersion, bool indexed allowed, bool indexed setDefault);

    /// @notice emitted when the status for a certain AvoForwarder version is updated
    event SetAvoForwarderVersion(address indexed avoForwarderVersion, bool indexed allowed);

    /// @notice emitted when the fee config is updated
    event FeeConfigUpdated(address indexed feeCollector, uint8 indexed mode, uint88 indexed fee);
}

abstract contract AvoVersionsRegistryCore is
    AvoVersionsRegistryConstants,
    AvoVersionsRegistryVariables,
    AvoVersionsRegistryErrors,
    AvoVersionsRegistryEvents
{
    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    /// @dev checks if an address is not the zero address
    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert AvoVersionsRegistry__InvalidParams();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(IAvoFactory avoFactory_) validAddress(address(avoFactory_)) AvoVersionsRegistryConstants(avoFactory_) {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }
}

abstract contract AvoFeeCollector is AvoVersionsRegistryCore {
    /// @inheritdoc IAvoFeeCollector
    function calcFee(uint256 gasUsed_) public view returns (uint256 feeAmount_, address payable feeCollector_) {
        FeeConfig memory feeConfig_ = feeConfig;

        if (feeConfig_.fee > 0) {
            if (feeConfig_.mode == 0) {
                // percentage of `gasUsed_` fee amount mode
                if (gasUsed_ == 0) {
                    revert AvoVersionsRegistry__InvalidParams();
                }

                // fee amount = gasUsed * gasPrice * fee percentage. (tx.gasprice is in wei)
                feeAmount_ = (gasUsed_ * tx.gasprice * feeConfig_.fee) / 1e8; // 1e8 = 100%
            } else if (feeConfig_.mode == 1) {
                // absolute fee amount mode
                feeAmount_ = feeConfig_.fee;
            } else {
                // theoretically not reachable because of check in `updateFeeConfig` but doesn't hurt to have this here
                revert AvoVersionsRegistry__FeeModeNotImplemented(feeConfig_.mode);
            }
        }

        return (feeAmount_, feeConfig_.feeCollector);
    }

    /***********************************|
    |            ONLY OWNER             |
    |__________________________________*/

    /// @notice sets `feeConfig_` as the new fee config in storage. Only callable by owner.
    function updateFeeConfig(FeeConfig calldata feeConfig_) external onlyOwner validAddress(feeConfig_.feeCollector) {
        if (feeConfig_.mode > 1) {
            revert AvoVersionsRegistry__FeeModeNotImplemented(feeConfig_.mode);
        }

        feeConfig = feeConfig_;

        emit FeeConfigUpdated(feeConfig_.feeCollector, feeConfig_.mode, feeConfig_.fee);
    }
}

contract AvoVersionsRegistry is AvoVersionsRegistryCore, AvoFeeCollector {
    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor(IAvoFactory avoFactory_) AvoVersionsRegistryCore(avoFactory_) {}

    /// @notice initializes the contract with `owner_` as owner
    function initialize(address owner_) public initializer validAddress(owner_) {
        _transferOwnership(owner_);
    }

    /// @notice clears storage slot 101. up to v3.0.0 `avoFactory` address was at that slot, since v3.0.0 feeConfig
    function reinitialize() public reinitializer(2) {
        assembly {
            sstore(0x65, 0) // overwrite storage slot 101 completely
        }
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    /// @inheritdoc IAvoVersionsRegistry
    function requireValidAvoWalletVersion(address avoWalletVersion_) external view {
        if (avoWalletVersions[avoWalletVersion_] != true) {
            revert AvoVersionsRegistry__InvalidVersion();
        }
    }

    /// @inheritdoc IAvoVersionsRegistry
    function requireValidAvoMultisigVersion(address avoMultisigVersion_) external view {
        if (avoMultisigVersions[avoMultisigVersion_] != true) {
            revert AvoVersionsRegistry__InvalidVersion();
        }
    }

    /// @inheritdoc IAvoVersionsRegistry
    function requireValidAvoForwarderVersion(address avoForwarderVersion_) public view {
        if (avoForwarderVersions[avoForwarderVersion_] != true) {
            revert AvoVersionsRegistry__InvalidVersion();
        }
    }

    /***********************************|
    |            ONLY OWNER             |
    |__________________________________*/

    /// @notice             sets the status for a certain address as allowed / default AvoWallet version.
    ///                     Only callable by owner.
    /// @param avoWallet_   the address of the contract to treat as AvoWallet version
    /// @param allowed_     flag to set this address as valid version (true) or not (false)
    /// @param setDefault_  flag to indicate whether this version should automatically be set as new
    ///                     default version for new deployments at the linked `avoFactory`
    function setAvoWalletVersion(
        address avoWallet_,
        bool allowed_,
        bool setDefault_
    ) external onlyOwner validAddress(avoWallet_) {
        if (!allowed_ && setDefault_) {
            // can't be not allowed but supposed to be set as default
            revert AvoVersionsRegistry__InvalidParams();
        }

        avoWalletVersions[avoWallet_] = allowed_;

        if (setDefault_) {
            // register the new version as default version at the linked AvoFactory
            avoFactory.setAvoWalletImpl(avoWallet_);
        }

        emit SetAvoWalletVersion(avoWallet_, allowed_, setDefault_);
    }

    /// @notice              sets the status for a certain address as allowed AvoForwarder version.
    ///                      Only callable by owner.
    /// @param avoForwarder_ the address of the contract to treat as AvoForwarder version
    /// @param allowed_      flag to set this address as valid version (true) or not (false)
    function setAvoForwarderVersion(
        address avoForwarder_,
        bool allowed_
    ) external onlyOwner validAddress(avoForwarder_) {
        avoForwarderVersions[avoForwarder_] = allowed_;

        emit SetAvoForwarderVersion(avoForwarder_, allowed_);
    }

    /// @notice             sets the status for a certain address as allowed / default AvoMultisig version.
    ///                     Only callable by owner.
    /// @param avoMultisig_ the address of the contract to treat as AvoMultisig version
    /// @param allowed_     flag to set this address as valid version (true) or not (false)
    /// @param setDefault_  flag to indicate whether this version should automatically be set as new
    ///                     default version for new deployments at the linked `avoFactory`
    function setAvoMultisigVersion(
        address avoMultisig_,
        bool allowed_,
        bool setDefault_
    ) external onlyOwner validAddress(avoMultisig_) {
        if (!allowed_ && setDefault_) {
            // can't be not allowed but supposed to be set as default
            revert AvoVersionsRegistry__InvalidParams();
        }

        avoMultisigVersions[avoMultisig_] = allowed_;

        if (setDefault_) {
            // register the new version as default version at the linked AvoFactory
            avoFactory.setAvoMultisigImpl(avoMultisig_);
        }

        emit SetAvoMultisigVersion(avoMultisig_, allowed_, setDefault_);
    }
}

