// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;


/**
 *    ,,                           ,,                                
 *   *MM                           db                      `7MM      
 *    MM                                                     MM      
 *    MM,dMMb.      `7Mb,od8     `7MM      `7MMpMMMb.        MM  ,MP'
 *    MM    `Mb       MM' "'       MM        MM    MM        MM ;Y   
 *    MM     M8       MM           MM        MM    MM        MM;Mm   
 *    MM.   ,M9       MM           MM        MM    MM        MM `Mb. 
 *    P^YbmdP'      .JMML.       .JMML.    .JMML  JMML.    .JMML. YA.
 *
 *    FlatPriceCurve.sol :: 0xc509733b8dddbab9369a96f6f216d6e59db3900f
 *    etherscan.io verified 2023-11-30
 */ 
import "./PriceCurveBase.sol";

contract FlatPriceCurve is PriceCurveBase {

  function calcOutput (uint input, bytes memory curveParams) public pure override returns (uint output) {
    uint basePriceX96 = abi.decode(curveParams, (uint));
    output = input * basePriceX96 / Q96;
  }

  // the only param for flat curve is uint basePriceX96, no calculations needed
  function calcCurveParams (bytes memory curvePriceData) public pure override returns (bytes memory curveParams) {
    curveParams = curvePriceData;
  }

}

