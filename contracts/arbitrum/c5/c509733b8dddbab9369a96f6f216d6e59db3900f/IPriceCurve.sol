// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

interface IPriceCurve {
  function getOutput (
    uint totalInput,
    uint filledInput,
    uint input,
    bytes memory curveParams
  ) external pure returns (uint output);
}

