// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { IBase } from "./IBase.sol";
import { Charge } from "./Structs.sol";
import { ERC20 } from "./ERC20.sol";

abstract contract Base is IBase {
    /*******************************
     * Errors *
     *******************************/

    error InvalidOperationIdVerification();
    error NotDiagonalBot();
    error NotDiagonalAdmin();
    error SafeCallError();
    error SafeCallOperationNotSuccessful();
    error InvalidFeeReciever();

    /*******************************
     * Constants *
     *******************************/

    /**
     * @notice Diagonal admin
     */
    address public constant DIAGONAL_ADMIN = 0x813c8659987179D4B77fC38667367a20A7E73548;

    /*******************************
     * State vars *
     *******************************/

    /**
     * @notice Organisation signer
     * @dev used for charge requests
     */
    address public signer;

    /**
     * @notice Operation ids
     * @dev we never delete the entries in this mapping
     */
    mapping(bytes32 => bool) public operationIds;

    /**
     * @notice Gap array, for further state variable changes
     */
    uint256[48] private __gap;

    /*******************************
     * Modifiers *
     *******************************/

    modifier onlyDiagonalBot() {
        if (!isBot(msg.sender)) revert NotDiagonalBot();
        _;
    }

    modifier onlyDiagonalAdmin() {
        if (msg.sender != DIAGONAL_ADMIN) revert NotDiagonalAdmin();
        _;
    }

    /*******************************
     * Functions start *
     *******************************/

    function _verifyAndSetNewOperationId(bytes32 operationId) internal {
        if (operationIds[operationId]) revert InvalidOperationIdVerification();
        operationIds[operationId] = true;
    }

    function _safeCall(address token, bytes memory data) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = token.call{ value: 0 }(data);

        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            }
            revert SafeCallError();
        }

        if (returndata.length > 0) {
            if (!abi.decode(returndata, (bool))) revert SafeCallOperationNotSuccessful();
        }
    }

    function isBot(address bot) public pure returns (bool) {
        if (bot == 0xdAfEF6179E02B73C620Ff9aE416ae8091eF0Cc33 || bot == 0xCef9Db135e6CDbB2E18Ba9ea1344E4b1561001Ab)
            return true;

        return false;
    }

    function withdrawFees(
        address token,
        address receiver,
        uint256 amount
    ) public onlyDiagonalAdmin {
        if (receiver == address(0)) revert InvalidFeeReciever();
        _safeCall(token, abi.encodeWithSelector(ERC20.transfer.selector, receiver, amount));
    }
}

