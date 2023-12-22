// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITokenTransferProxy.sol";
import "./AccessHandler.sol";
import "./IERC20.sol";

/**
 * @title Token Transfer Proxy
 * @author Deepp Dev Team
 * @notice This contract is used to transfer tokens on the owners behalf.
 * @notice This is a util contract for the BookieMain app.
 * @notice Accesshandler is Initializable.
 */
contract TokenTransferProxy is AccessHandler, ITokenTransferProxy {

    /**
     * @notice Constructor that just initializes.
     */
    constructor() {
        BaseInitializer.initialize();
    }

    /**
     * @notice Uses `transferFrom` and ERC20 approval to transfer tokens.
     * @param token The address of the ERC20 token type to transfer.
     * @param from The address of the user.
     * @param to The destination address.
     * @param value The amount to transfer.
     */
    function transferFrom(
        address token,
        address from,
        address to,
        uint256 value
    )
        public
        override
        onlyRole(TRANSFER_ROLE)
        returns (bool)
    {
        return IERC20(token).transferFrom(from, to, value);
    }
}
