// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { IDiagonalTimelockController } from "./IDiagonalTimelockController.sol";
import { TimelockController } from "./TimelockController.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";

/**
 * @title  DiagonalTimelockController contract
 * @author Diagonal Finance
 */
contract DiagonalTimelockController is IDiagonalTimelockController, TimelockController {
    /*******************************
     * Errors *
     *******************************/

    error InvalidPauseControllerAddress();
    error PausableOperationError();
    error PausableOperationNotSuccessful();

    /*******************************
     * Constants *
     *******************************/

    bytes32 public constant PAUSE_CONTROLLER_ROLE = keccak256("PAUSE_CONTROLLER_ROLE");

    /*******************************
     * Constructor *
     *******************************/

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin,
        address pauseController
    ) TimelockController(minDelay, proposers, executors, admin) {
        if (pauseController == address(0)) revert InvalidPauseControllerAddress();

        _setupRole(PAUSE_CONTROLLER_ROLE, pauseController);
    }

    /*******************************
     * Functions start *
     *******************************/

    function pause(address target) external override onlyRole(PAUSE_CONTROLLER_ROLE) {
        if (!_isContract(target)) revert PausableOperationError();

        _safePauseCall(target, abi.encodeWithSignature("pause()"));
    }

    function unpause(address target) external override onlyRole(PAUSE_CONTROLLER_ROLE) {
        if (!_isContract(target)) revert PausableOperationError();

        _safePauseCall(target, abi.encodeWithSignature("unpause()"));
    }

    function _safePauseCall(address target, bytes memory data) private {
        // NOTE: This method assumes "pause()", and "unpause()", do not return values.
        // Handling return value would involve extra checks.

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: 0 }(data);

        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            }
            revert PausableOperationError();
        }
    }

    function _isContract(address addr) private view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return addr.code.length > 0;
    }
}

