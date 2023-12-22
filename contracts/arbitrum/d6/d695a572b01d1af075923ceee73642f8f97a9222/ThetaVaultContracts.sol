// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./ThetaVault.sol";
import "./MegaThetaVault.sol";
import "./HedgedThetaVault.sol";
import "./DisabledThetaVault.sol";

contract CVIUSDCThetaVault is DisabledThetaVault {
  constructor() DisabledThetaVault() {}
}

contract CVIUSDCThetaVaultV3 is ThetaVault {
  constructor() ThetaVault() {}
}

contract UCVIUSDCThetaVaultV3 is ThetaVault {
  constructor() ThetaVault() {}
}

contract CVIUSDCMegaThetaVault is MegaThetaVault {
  constructor() MegaThetaVault() {}
}

contract CVIUSDCHedgedThetaVault is HedgedThetaVault {
  constructor() HedgedThetaVault() {}
}

