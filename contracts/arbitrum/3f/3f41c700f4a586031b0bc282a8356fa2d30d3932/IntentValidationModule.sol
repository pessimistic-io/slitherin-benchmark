// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {AccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";
import {BaseUpgradeableModule} from "./BaseUpgradeableModule.sol";
import {IAuthorization} from "./IAuthorization.sol";
import {IDeviceValidation} from "./IDeviceValidation.sol";

import {ModuleRegistry} from "./ModuleRegistry.sol";

contract IntentValidationModule is
    BaseUpgradeableModule,
    AccessControlEnumerableUpgradeable,
    IDeviceValidation
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    uint256 public constant MAX_DEVICES = 50;

    bytes32 public constant MODULE_ID = keccak256("MODULE_INTENT_VALIDATION");
    bytes32 public constant ROLE_MODULE_OWNER = keccak256("ROLE_MODULE_OWNER");
    bytes32 constant AUTHORIZATION_MODULE = keccak256("MODULE_AUTHORIZATION");

    /// @dev This is emitted when a new is key is added for the account-device unique pair
    event DeviceKeyAdded(address indexed account, uint256 indexed deviceId);
    /// @dev This is emitted when an existing key is updated for the account-device unique pair
    event DeviceKeyUpdated(address indexed account, uint256 indexed deviceId);
    /// @dev This is emitted when a new is key is removed for the account-device unique pair
    event DeviceKeyRemoved(address indexed account, uint256 indexed deviceId);

    mapping(address => EnumerableSetUpgradeable.UintSet) devicesMap;
    mapping(address => mapping(uint256 => string)) deviceKeyMap;

    modifier onlyAdmin() {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAdminAccount(msg.sender),
            "CALLER_IS_NOT_AN_ADMIN"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _moduleOwner,
        address _modRegistry
    ) public initializer {
        require(_moduleOwner != address(0), "INVALID_ADDRESS");
        require(_modRegistry != address(0), "INVALID_REGISTRY_ADDRESS");
        __BaseUpgradeableModule_init();
        __AccessControlEnumerable_init();
        modules = ModuleRegistry(_modRegistry);
        _grantRole(DEFAULT_ADMIN_ROLE, _moduleOwner);
        _setRoleAdmin(ROLE_MODULE_OWNER, ROLE_MODULE_OWNER);
        _grantRole(ROLE_MODULE_OWNER, _moduleOwner);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(ROLE_MODULE_OWNER) {}

    function getVersion() external pure virtual override returns (uint8) {
        return 1;
    }

    /**
     * @notice Adds a key for the unique account-deviceId pair
     *
     * @dev The deviceId and key are generated off-chain and on a per account basis,
     *      this implies the same value for any deviceId and/or key could be the same
     *      for multiple accounts.
     *
     * @param account The address of the shareholder's account
     * @param deviceId The ID of the device
     * @param key The key associated with the unique account-deviceId pair
     *
     */
    function setDeviceKey(
        address account,
        uint256 deviceId,
        string memory key
    ) external virtual override onlyAdmin {
        if (devicesMap[account].add(deviceId)) {
            emit DeviceKeyAdded(account, deviceId);
        } else {
            emit DeviceKeyUpdated(account, deviceId);
        }
        deviceKeyMap[account][deviceId] = key;
    }

    /**
     * @notice Removes the key associated to the unique account-deviceId pair
     *
     * @dev The deviceId should exist or this operation will revert with an error.
     *
     * @param account The address of the shareholder's account
     * @param deviceId The ID of the device
     *
     */
    function clearDeviceKey(
        address account,
        uint256 deviceId
    ) external virtual override onlyAdmin {
        require(devicesMap[account].length() != 0, "INVALID_ACCOUNT");
        _removeDeviceKey(account, deviceId);
    }

    /**
     * @notice Removes all the device's keys associated with the given account
     *
     * @dev The account should exist or this operation will revert with an error.
     *
     * @param account The address of the shareholder's account
     *
     */
    function clearAccountKeys(
        address account
    ) external virtual override onlyAdmin {
        uint256[] memory devices = devicesMap[account].values();
        for (uint256 i = 0; i < devices.length; ) {
            _removeDeviceKey(account, devices[i]);
            unchecked {
                i++;
            }
        }
    }

    function getDeviceKey(
        address account,
        uint256 deviceId
    ) external view virtual returns (string memory key) {
        require(devicesMap[account].contains(deviceId), "INVALID_DEVICE_ID");
        key = deviceKeyMap[account][deviceId];
    }

    function getDeviceKeys(
        address account
    )
        external
        view
        virtual
        override
        returns (uint256[] memory devices, string[] memory keys)
    {
        devices = devicesMap[account].values();
        keys = new string[](devicesMap[account].length());
        for (uint256 i = 0; i < devicesMap[account].length(); ) {
            keys[i] = deviceKeyMap[account][devices[i]];
            unchecked {
                i++;
            }
        }
    }

    function hasDevices(
        address account
    ) external view virtual override returns (bool) {
        return devicesMap[account].length() != 0;
    }

    // -------------------- Internal --------------------  //

    function _removeDeviceKey(
        address account,
        uint256 deviceId
    ) internal virtual {
        require(devicesMap[account].contains(deviceId), "INVALID_DEVICE_ID");
        delete deviceKeyMap[account][deviceId];
        devicesMap[account].remove(deviceId);
        emit DeviceKeyRemoved(account, deviceId);
    }
}

