// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FCNVaultViewer } from "./FCNVaultViewer.sol";
import { FCNProductViewer } from "./FCNProductViewer.sol";
import { LOVProductViewer } from "./LOVProductViewer.sol";

contract CegaViewer is FCNVaultViewer, FCNProductViewer, LOVProductViewer {}

