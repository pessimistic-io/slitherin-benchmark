// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

import "./IPriceCurve.sol";

error MaxInputExceeded(uint remainingInput);

abstract contract PriceCurveBase is IPriceCurve {

  uint256 public constant Q96 = 0x1000000000000000000000000;

  function getOutput (
    uint totalInput,
    uint filledInput,
    uint input,
    bytes memory curveParams
  ) public pure returns (uint output) {
    requireInputRemaining(totalInput, filledInput, input);

    uint filledOutput = calcOutput(filledInput, curveParams);
    uint totalOutput = calcOutput(filledInput + input, curveParams);

    output = totalOutput - filledOutput;
  }
  
  function requireInputRemaining (uint totalInput, uint filledInput, uint input) internal pure {
    uint remainingInput = totalInput - filledInput;
    if (input > remainingInput) {
      revert MaxInputExceeded(remainingInput);
    }
  }

  function calcOutput (uint input, bytes memory curveParams) public pure virtual returns (uint output);
  function calcCurveParams (bytes memory curvePriceData) public pure virtual returns (bytes memory curveParams);

}

