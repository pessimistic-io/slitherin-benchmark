// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { ICoreAccessControlV1 } from "./ICoreAccessControlV1.sol";
import { ICoreDepositV1 } from "./ICoreDepositV1.sol";
import { ICoreStopGuardianV1 } from "./ICoreStopGuardianV1.sol";
import { ICoreWithdrawV1 } from "./CoreWithdraw.sol";

// This interface cannot be implemented on BaseTransfers.sol, but it's accurate
// since BaseTransfers.sol only inherits and overrides methods, and does not define
// additional public/external methods.

interface IBaseTransfersV1 is ICoreDepositV1, ICoreWithdrawV1, ICoreAccessControlV1, ICoreStopGuardianV1 {

}

