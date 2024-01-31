// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC721BaseController } from "./IERC721BaseController.sol";
import { IERC721ApprovableController } from "./IERC721ApprovableController.sol";
import { IERC721TransferableController } from "./IERC721TransferableController.sol";

/**
 * @title Partial ERC721 interface required by controller functions
 */
interface IERC721Controller is
    IERC721TransferableController,
    IERC721ApprovableController,
    IERC721BaseController
{}

