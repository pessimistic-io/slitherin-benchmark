// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC165.sol";

/// @title Interface Staake Sale
abstract contract IEarlySaleReceiver is ERC165 {
    /**
     * @notice deposit previous purchases of STK
     */
    function earlyDeposit(
        address _investor,
        uint256 _eth,
        uint256 _stk
    ) external virtual;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return
            interfaceId == type(IEarlySaleReceiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

