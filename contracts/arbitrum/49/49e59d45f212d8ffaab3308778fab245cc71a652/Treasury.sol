// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract Treasury is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    bytes32 public constant REFERRAL_DISBURSAL_ROLE =
        keccak256("REFERRAL_DISBURSAL_ROLE");

    event FundWithdrawn(
        IERC20Upgradeable tokenAddress,
        address to,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice  Initialize contract,provides _superAdmin wallet address DEFAULT_ADMIN and ADMIN role and sets role ADMIN as a role admin for PLATFORM and REFERRAL_DISBURSAL role  .
     * @param   _superAdmin  .
     */
    function initialize(address _superAdmin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _superAdmin);
        _grantRole(ADMIN_ROLE, _superAdmin);
        _setRoleAdmin(PLATFORM_ROLE, ADMIN_ROLE);
        _setRoleAdmin(REFERRAL_DISBURSAL_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Provides functionality to check if the given account has Admin role .
     * @param   _account  Address of the account to check the ADMIN_ROLE for.
     * @return  bool  .
     */
    function isAdmin(address _account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, _account);
    }

    /**
     * @notice Provides functionality to check if the given account has REFERRAL_DISBURSAL role .
     * @param   _account  Address of the account to check the REFERRAL_DISBURSAL for.
     * @return  bool  .
     */
    function isReferralDisburser(
        address _account
    ) external view returns (bool) {
        return hasRole(REFERRAL_DISBURSAL_ROLE, _account);
    }

    /**
     * @notice Provides functionality to check if the given account has Platform role .
     * @param   _account  Address of the account to check the PLATFORM_ROLE for.
     * @return  bool  .
     */
    function isPlatformWallet(address _account) external view returns (bool) {
        return hasRole(PLATFORM_ROLE, _account);
    }

    /**
     * @notice  Provides functionality to withdraw ERC20 token from the contract,caller must have Admin role .
     * @param   _tokenAddress Address of ERC20 token to withdraw
     * @param   _to Address where the withdrawn tokens are to be transferred.
     * @param   _amount  Amount of token to withdraw
     */
    function withdrawFunds(
        IERC20Upgradeable _tokenAddress,
        address _to,
        uint256 _amount
    ) external onlyRole(ADMIN_ROLE) {
        _tokenAddress.safeTransfer(_to, _amount);
        emit FundWithdrawn(_tokenAddress, _to, _amount);
    }

    /**
     * @notice  Provides functionality to upgrade the contract by adding new implementation contract,caller must have Admin role .
     * @param   _newImplementation  .
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}
}

