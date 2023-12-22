// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IHandle.sol";
import "./IReferral.sol";
import "./HandlePausable.sol";
import "./Roles.sol";

/**
 * @dev Holds referral data.
 */
contract Referral is
    IReferral,
    Initializable,
    UUPSUpgradeable,
    HandlePausable,
    Roles
{
    /** @dev The Handle contract interface */
    IHandle private handle;

    /** @dev mapping(user => referrer) */
    mapping(address => address) private referrals;

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyAdmin {
        handle = IHandle(_handle);
        grantRole(OPERATOR_ROLE, handle.comptroller());
        grantRole(OPERATOR_ROLE, handle.treasury());
        grantRole(OPERATOR_ROLE, handle.liquidator());
        grantRole(OPERATOR_ROLE, handle.fxKeeperPool());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Sets referral for given user if not yet set
     * @param userAccount The address from the user being referred
     * @param referralAccount The address from the user referring
     */
    function setReferral(address userAccount, address referralAccount)
        external
        override
        onlyOperator
    {
        if (referrals[userAccount] != address(0)) return;
        // If there's no referral, clear the empty flag
        // and set the user as their own referral.
        if (referralAccount == address(0)) referralAccount = userAccount;
        referrals[userAccount] = referralAccount;
    }

    /**
     * @dev Getter for user referral address
     * @param userAccount The address of the user referred
     */
    function getReferral(address userAccount)
        external
        view
        override
        returns (address)
    {
        return referrals[userAccount];
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

