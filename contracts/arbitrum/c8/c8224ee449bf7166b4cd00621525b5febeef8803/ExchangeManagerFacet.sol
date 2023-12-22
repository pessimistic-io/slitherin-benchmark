// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { LibDiamond } from "./LibDiamond.sol";
import { LibAccessControl } from "./LibAccessControl.sol";
import { LibAllowList } from "./LibAllowList.sol";

error CannotAuthoriseSelf();

contract ExchangeManagerFacet {

    function addExchange(address _exchange) external {
        if (msg.sender != LibDiamond.contractOwner()) LibAccessControl.isAllowedTo();

        if (_exchange == address(this)) revert CannotAuthoriseSelf();

        LibAllowList.addAllowedContract(_exchange);
    }

    function batchAddExchange(address[] calldata _exchanges) external {
        if (msg.sender != LibDiamond.contractOwner()) LibAccessControl.isAllowedTo();

        uint256 numExchange = _exchanges.length;

        for (uint256 i = 0; i < numExchange; ) {
            address exchange = _exchanges[i];
            if (exchange == address(this)) revert CannotAuthoriseSelf();
            if (LibAllowList.isContractAllowed(exchange)) continue;
            LibAllowList.addAllowedContract(exchange);
            unchecked {
                ++i;
            }
        }
    }

    function removeExchange(address _exchange) external {
        if (msg.sender != LibDiamond.contractOwner()) LibAccessControl.isAllowedTo();

        if (!LibAllowList.isContractAllowed(_exchange)) return;
        LibAllowList.removeAllowedContract(_exchange);
    }

    function batchRemoveExchange(address[] calldata _exchanges) external {
        if (msg.sender != LibDiamond.contractOwner()) LibAccessControl.isAllowedTo();

        uint256 numExchange = _exchanges.length;

        for (uint256 i = 0; i < numExchange; ) {
            address exchange = _exchanges[i];
            LibAllowList.removeAllowedContract(exchange);
            unchecked {
                ++i;
            }
        }
    }

    function allowedExchanges() external view returns (address[] memory ) {
        return LibAllowList.getAllAllowedContract();
    }
}
