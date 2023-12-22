// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./MixedLP.sol";

contract DLP is MixedLP{
  constructor() MixedLP("DLP","DLP"){
  }
}
