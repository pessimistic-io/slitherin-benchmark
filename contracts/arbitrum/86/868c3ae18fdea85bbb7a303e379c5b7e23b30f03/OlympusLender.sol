// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {LENDRv1} from "./LENDR.v1.sol";
import "./Kernel.sol";

import {ILendingAMO} from "./ILendingAMO.sol";

/// @title  Olympus Lender
/// @notice Olympus Lender (Module) Contract
contract OlympusLender is LENDRv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("LENDR");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc LENDRv1
    function addAMO(address amo_) external override permissioned {
        // Check that AMO complies with the correct interface
        if (!_isAMO(amo_)) revert LENDR_InvalidInterface(amo_);

        // Check that AMO is not already installed
        if (isAMOInstalled[amo_]) revert LENDR_AMOAlreadyInstalled(amo_);

        // Install AMO
        isAMOInstalled[amo_] = true;
        activeAMOs.push(amo_);
        ++activeAMOCount;

        emit AMOAdded(amo_);
    }

    /// @inheritdoc LENDRv1
    function removeAMO(address amo_) external override permissioned {
        // Find index of AMO in array
        for (uint256 i; i < activeAMOCount; ) {
            if (activeAMOs[i] == amo_) {
                // Flag as no longer installed
                isAMOInstalled[amo_] = false;

                // Delete AMO from array by swapping with last element and popping
                activeAMOs[i] = activeAMOs[activeAMOCount - 1];
                activeAMOs.pop();
                --activeAMOCount;

                emit AMORemoved(amo_);

                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc LENDRv1
    function getDeployedOhm(address amo_) external view override returns (uint256) {
        uint256 deployedOhm = ILendingAMO(amo_).ohmDeployed();
        return deployedOhm;
    }

    /// @inheritdoc LENDRv1
    function getTotalDeployedOhm() external view override returns (uint256) {
        uint256 deployedOhm;

        for (uint256 i; i < activeAMOCount; ) {
            deployedOhm += ILendingAMO(activeAMOs[i]).ohmDeployed();

            unchecked {
                ++i;
            }
        }

        return deployedOhm;
    }

    /// @inheritdoc LENDRv1
    function getBorrowedOhm(address amo_) external view override returns (uint256) {
        uint256 borrowedOhm = ILendingAMO(amo_).getBorrowedOhm();
        return borrowedOhm;
    }

    /// @inheritdoc LENDRv1
    function getTotalBorrowedOhm() external view override returns (uint256) {
        uint256 borrowedOhm;

        for (uint256 i; i < activeAMOCount; ) {
            borrowedOhm += ILendingAMO(activeAMOs[i]).getBorrowedOhm();

            unchecked {
                ++i;
            }
        }

        return borrowedOhm;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    /// @inheritdoc LENDRv1
    function _isAMO(address amo_) internal view override returns (bool) {
        if (amo_.code.length == 0) return false;

        ILendingAMO amo = ILendingAMO(amo_);

        try amo.ohmDeployed() {} catch (bytes memory) {
            return false;
        }

        try amo.getBorrowedOhm() {} catch (bytes memory) {
            return false;
        }

        return true;
    }
}

