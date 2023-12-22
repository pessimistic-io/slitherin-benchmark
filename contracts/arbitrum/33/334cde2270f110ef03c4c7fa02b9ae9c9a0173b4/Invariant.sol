// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import { IPlsRdntLens } from "./PlsRdntLens.sol";
import "./IERC20.sol";

interface IInvariant {
  function checkHold() external view;

  error INVARIANT_VIOLATION();
}

contract Invariant is IInvariant {
  IPlsRdntLens public immutable LENS;
  address public immutable PLSRDNT;
  address public immutable PLSRDNTV2;
  address public immutable VDLP;

  constructor(address _plsrdnt, address _plsrdntv2, address _vdlp, IPlsRdntLens _lens) {
    PLSRDNT = _plsrdnt;
    PLSRDNTV2 = _plsrdntv2;
    VDLP = _vdlp;
    LENS = _lens;
  }

  function checkHold() external view {
    // assumptions: 1 vDLP == 1 DLP, 1 plsRDNT == 1 DLP
    // vDLP supply + plsRDNT supply = locked DLP + DLP threshold in old depositor + DLP threshold in new depositor
    if (IERC20(VDLP).totalSupply() + IERC20(PLSRDNT).totalSupply() != LENS.totalDlpBalance())
      revert INVARIANT_VIOLATION();

    // plsRDNTV2.getrate() * plsRDNTV2.totalSupply() = vDLP.totalSupply()
    // need to be careful with this one because of rounding issues
  }

  function checkHoldReturn() external view returns (bool) {
    // assumptions: 1 vDLP == 1 DLP, 1 plsRDNT == 1 DLP
    // vDLP supply + plsRDNT supply = locked DLP + DLP threshold in old depositor + DLP threshold in new depositor
    if (IERC20(VDLP).totalSupply() + IERC20(PLSRDNT).totalSupply() != LENS.totalDlpBalance()) return false;

    // plsRDNTV2.getrate() * plsRDNTV2.totalSupply() = vDLP.totalSupply()
    // need to be careful with this one because of rounding issues

    return true;
  }
}

