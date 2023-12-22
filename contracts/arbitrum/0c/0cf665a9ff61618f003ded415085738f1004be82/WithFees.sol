// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IWithFees} from "./IWithFees.sol";

/**
 * @title WithFees
 * @notice This contract is responsible for managing, calculating and transferring fees.
 */
contract WithFees is IAccessControlHolder, IWithFees {
    address public immutable override treasury;
    uint256 public immutable override fees;
    IAccessControl public immutable override acl;
    bytes32 public constant FEES_MANAGER = keccak256("FEES_MANAGER");

    /**
     * @notice Modifier to allow only function calls that are accompanied by the required fee.
     * @dev Function reverts with OnlyWithFees error, if the value is smaller than expected.
     */
    modifier onlyWithFees() {
        if (fees != msg.value) {
            revert OnlyWithFees();
        }
        _;
    }

    /**
     * @notice Modifier to allow only accounts with FEES_MANAGER role.
     * @dev Reverts with OnlyFeesManagerAccess error, if the sender does not have the role.
     */
    modifier onlyFeesManagerAccess() {
        if (!acl.hasRole(FEES_MANAGER, msg.sender)) {
            revert OnlyFeesManagerAccess();
        }
        _;
    }

    constructor(IAccessControl acl_, address treasury_, uint256 value_) {
        acl = acl_;
        treasury = treasury_;
        fees = value_;
    }

    /**
     * @notice Transfers the balance of the contract to the treasury.
     * @dev  Only accessible by an account with the FEES_MANAGER role.
     */
    function transfer() external onlyFeesManagerAccess {
        (bool sent, ) = treasury.call{value: address(this).balance}("");
        if (!sent) {
            revert ETHTransferFailed();
        }
    }
}

