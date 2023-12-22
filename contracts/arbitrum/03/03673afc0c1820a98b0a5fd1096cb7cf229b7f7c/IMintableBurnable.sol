// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IMintable.sol";
import "./IBurnable.sol";

interface IMintableBurnable is IMintable, IBurnable {}

