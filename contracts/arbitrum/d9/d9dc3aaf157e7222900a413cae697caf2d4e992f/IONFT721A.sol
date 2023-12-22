// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IONFT721ACore.sol";
import "./IERC721ASpecific.sol";

/**
 * @dev Interface of the ONFT standard
 */
interface IONFT721A is IONFT721ACore, IERC721ASpecific {

    function supportsInterface(bytes4 interfaceId) external view override(IERC165, IERC721ASpecific) returns (bool);
}
