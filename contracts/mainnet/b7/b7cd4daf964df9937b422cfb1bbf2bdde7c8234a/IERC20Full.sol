// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./IERC20Metadata.sol";
import "./draft-IERC20Permit.sol";

interface IERC20Full is IERC20Metadata, IERC20Permit {
    /** This function might not exist */
    function version() external view returns (string memory);
}
