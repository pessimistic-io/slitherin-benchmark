// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./AccessControlEnumerable.sol";
import "./BeaconProxy.sol";
import "./StringsUpgradeable.sol";

interface ISpiceFiFactory {
    function ASSET_ROLE() external view returns (bytes32);

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
}

/**
 * @title VaultFactory
 * @author Spice Finance Inc
 */
contract VaultFactory is AccessControlEnumerable {
    using StringsUpgradeable for uint256;

    /// @notice Beacon address
    address public immutable beacon;

    /// @notice SpiceFiFactory
    ISpiceFiFactory public immutable factory;

    /// @notice Spice dev wallet
    address public dev;

    /// @notice Spice Multisig address
    address public multisig;

    /// @notice Fee recipient address
    address public feeRecipient;

    /*************/
    /* Constants */
    /*************/

    /// @notice Marketplace role
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");

    /// @notice Vault role
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    /**********/
    /* Errors */
    /**********/

    /// @notice Invalid address (e.g. zero address)
    error InvalidAddress();

    /// @notice Missing Role
    /// @param role Role
    /// @param user User address
    error MissingRole(bytes32 role, address user);

    /**********/
    /* Events */
    /**********/

    /// @notice Emitted when new vault is created
    /// @param owner Owner addres
    /// @param vault Vault address
    event VaultCreated(address indexed owner, address vault);

    /// @notice Emitted when dev is updated
    /// @param dev New dev address
    event DevUpdated(address dev);

    /// @notice Emitted when multisig is updated
    /// @param multisig New multisig address
    event MultisigUpdated(address multisig);

    /// @notice Emitted when fee recipient is updated
    /// @param feeRecipient New fee recipient address
    event FeeRecipientUpdated(address feeRecipient);

    /***************/
    /* Constructor */
    /***************/

    /// @notice Constructor
    /// @param _beacon Beacon address
    /// @param _factory SpiceFiFactory contract
    /// @param _dev Initial dev address
    /// @param _multisig Initial multisig address
    /// @param _feeRecipient Initial fee recipient address
    constructor(
        address _beacon,
        address _factory,
        address _dev,
        address _multisig,
        address _feeRecipient
    ) {
        if (address(_beacon) == address(0)) {
            revert InvalidAddress();
        }
        if (_factory == address(0)) {
            revert InvalidAddress();
        }
        if (_dev == address(0)) {
            revert InvalidAddress();
        }
        if (_multisig == address(0)) {
            revert InvalidAddress();
        }
        if (_feeRecipient == address(0)) {
            revert InvalidAddress();
        }

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        beacon = _beacon;
        factory = ISpiceFiFactory(_factory);
        dev = _dev;
        multisig = _multisig;
        feeRecipient = _feeRecipient;
    }

    /***********/
    /* Setters */
    /***********/

    /// @notice Set the dev wallet address
    ///
    /// Emits a {DevUpdated} event.
    ///
    /// @param _dev New dev wallet
    function setDev(address _dev) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dev == address(0)) {
            revert InvalidAddress();
        }
        dev = _dev;
        emit DevUpdated(_dev);
    }

    /// @notice Set the multisig address
    ///
    /// Emits a {MultisigUpdated} event.
    ///
    /// @param _multisig New multisig address
    function setMultisig(
        address _multisig
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_multisig == address(0)) {
            revert InvalidAddress();
        }
        multisig = _multisig;
        emit MultisigUpdated(_multisig);
    }

    /// @notice Set the fee recipient address
    ///
    /// Emits a {FeeRecipientUpdated} event.
    ///
    /// @param _feeRecipient New fee recipient address
    function setFeeRecipient(
        address _feeRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeRecipient == address(0)) {
            revert InvalidAddress();
        }
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /*************/
    /* Functions */
    /*************/

    /// @notice Creates new Vault vault
    /// @param asset Asset address for Vault
    /// @param marketplaces Marketplaces
    /// @return vault Created vault address
    function createVault(
        address asset,
        address[] calldata marketplaces
    ) external returns (address vault) {
        if (asset == address(0)) {
            revert InvalidAddress();
        }

        bytes32 ASSET_ROLE = factory.ASSET_ROLE();
        if (!factory.hasRole(ASSET_ROLE, asset)) {
            revert MissingRole(ASSET_ROLE, asset);
        }

        uint256 length = marketplaces.length;
        for (uint256 i; i != length; ++i) {
            _checkRole(MARKETPLACE_ROLE, marketplaces[i]);
        }

        uint256 vaultId = getRoleMemberCount(VAULT_ROLE) + 1;
        vault = address(
            new BeaconProxy(
                beacon,
                abi.encodeWithSignature(
                    "initialize(string,string,address,address[],address,address,address,address)",
                    string(
                        abi.encodePacked("Spice", vaultId.toString(), "Vault")
                    ),
                    string(abi.encodePacked("s", vaultId.toString(), "v")),
                    asset,
                    marketplaces,
                    msg.sender,
                    dev,
                    multisig,
                    feeRecipient
                )
            )
        );

        // grant VAULT_ROLE for tracking
        _grantRole(VAULT_ROLE, address(vault));

        emit VaultCreated(msg.sender, address(vault));
    }
}

