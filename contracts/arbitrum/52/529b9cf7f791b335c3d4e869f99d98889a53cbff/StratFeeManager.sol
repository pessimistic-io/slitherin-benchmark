// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./PausableUpgradeable.sol";
import "./IAdminStructure.sol";

/// @title StratFeeManager
/// @dev Contract that manages the fees for a strategy.
abstract contract StratFeeManager is PausableUpgradeable {
    // Address of contract that stores the information of the admins.
    IAdminStructure public adminStructure;
    /// @notice Address of the vault contract.
    address public vault;
    /// @notice Address of the Uniswap V3 router.
    address public unirouterV3;
    /// @notice Performance fee for the strategy.
    uint256 public performanceFee;
    /// @notice Management fee for the strategy.
    uint256 public managementFee;
    /// @notice Address of the performance fee recipient.
    address public performanceFeeRecipient;
    /// @notice Address of the management fee recipient.
    address public managementFeeRecipient;

    /// @dev Cap for performance and management fees.
    uint256 public constant FEE_CAP = 50 ether;
    /// @dev Value representing 100%.
    uint256 public constant ONE_HUNDRED = 100 ether;

    /// @dev Struct for common addresses used in initialization.
    struct CommonAddresses {
        IAdminStructure adminStructure;
        address vault;
        address unirouterV3;
        uint256 performanceFee;
        uint256 managementFee;
        address performanceFeeRecipient;
        address managementFeeRecipient;
    }

    /// @notice Emitted when the vault address is set.
    event SetVault(address vault);
    /// @notice Emitted when the Uniswap V3 router address is set.
    event SetUnirouterV3(address unirouter);
    /// @notice Emitted when the performance fee is set.
    event SetPerformanceFee(uint256 feeAmount);
    /// @notice Emitted when the management fee is set.
    event SetManagementFee(uint256 feeAmount);
    /// @notice Emitted when the performance fee recipient is set.
    event SetPerformanceFeeRecipient(address recipient);
    /// @notice Emitted when the management fee recipient is set.
    event SetManagementFeeRecipient(address recipient);

    /// @dev Initializes the contract.
    /// @param _commonAddresses Struct containing common addresses for initialization.
    function __StratFeeManager_init(
        CommonAddresses memory _commonAddresses
    ) internal onlyInitializing {
        adminStructure = _commonAddresses.adminStructure;
        require(address(adminStructure) != address(0), "ZeroAdminStructure");
        vault = _commonAddresses.vault;
        unirouterV3 = _commonAddresses.unirouterV3;

        performanceFeeRecipient = _commonAddresses.performanceFeeRecipient;
        managementFeeRecipient = _commonAddresses.managementFeeRecipient;

        performanceFee = _commonAddresses.performanceFee;
        managementFee = _commonAddresses.managementFee;
        require(performanceFee <= FEE_CAP, "PerformanceFeeCap");
        require(managementFee <= FEE_CAP, "ManagementFeeCap");
    }

    /// @dev Modifier to restrict access to super admin only.
    modifier onlySuperAdmin() {
        adminStructure.isValidSuperAdmin(msg.sender);
        _;
    }
    /// @dev Modifier to restrict access to admins and super admins only.
    modifier onlyAdmin() {
        adminStructure.isValidAdmin(msg.sender);
        _;
    }

    /// @dev Sets the performance fee for the strategy.
    /// @param _fee The new performance fee
    function setPerformanceFee(uint256 _fee) external onlyAdmin {
        require(_fee <= FEE_CAP, "PerformanceFeeCap");
        performanceFee = _fee;
        emit SetPerformanceFee(_fee);
    }

    /// @dev Sets the management fee for the strategy.
    /// @param _fee The new management fee
    function setManagementFee(uint256 _fee) external onlyAdmin {
        require(_fee <= FEE_CAP, "ManagementFeeCap");
        managementFee = _fee;
        emit SetManagementFee(_fee);
    }

    /// @dev Sets the performance fee recipient address.
    /// @param recipient The new performance fee recipient address
    function setPerformanceFeeRecipient(address recipient) external onlySuperAdmin {
        performanceFeeRecipient = recipient;
        emit SetPerformanceFeeRecipient(recipient);
    }

    /// @dev Sets the management fee recipient address.
    /// @param recipient The new management fee recipient address
    function setManagementFeeRecipient(address recipient) external onlySuperAdmin {
        managementFeeRecipient = recipient;
        emit SetManagementFeeRecipient(recipient);
    }

    /// @dev Sets the vault address.
    /// @param _vault The new vault address
    function setVault(address _vault) external onlySuperAdmin {
        vault = _vault;
        emit SetVault(_vault);
    }

    /// @dev Sets the Uniswap V3 router address.
    /// @param _unirouterV3 The new Uniswap V3 router address
    function setUnirouterV3(address _unirouterV3) external onlySuperAdmin {
        unirouterV3 = _unirouterV3;
        emit SetUnirouterV3(_unirouterV3);
    }

    uint256[60] private __gap;
}

