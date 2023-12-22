// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ToggleGovernance } from "./ToggleGovernance.sol";
import { IERC1155Supply } from "./IERC1155Supply.sol";

contract ToggleGovernanceFactory {
    function deployNewToggleGovernor(
        IERC1155Supply governanceToken,
        uint256 governanceTokenId
    )
        external
        returns (address)
    {
        return address(new ToggleGovernance(governanceToken, governanceTokenId));
    }
}

