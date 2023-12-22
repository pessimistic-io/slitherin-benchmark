// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./CustomErrors.sol";

library Interest {

  function PVToFV(
                  uint64 APR,
                  uint PV,
                  uint sTime,
                  uint eTime,
                  uint mantissaAPR
                  ) internal pure returns(uint){

    if (sTime >= eTime) {
      revert CustomErrors.INT_InvalidTimeInterval();
    }

    // Seconds per 365-day year (60 * 60 * 24 * 365)
    uint year = 31536000;
    
    // elapsed time from now to maturity
    uint elapsed = eTime - sTime;

    uint interest = PV * APR * elapsed / mantissaAPR / year;

    return PV + interest;    
  }

  function FVToPV(
                  uint64 APR,
                  uint FV,
                  uint sTime,
                  uint eTime,
                  uint mantissaAPR
                  ) internal pure returns(uint){

    if (sTime >= eTime) {
      revert CustomErrors.INT_InvalidTimeInterval();
    }

    // Seconds per 365-day year (60 * 60 * 24 * 365)
    uint year = 31536000;
    
    // elapsed time from now to maturity
    uint elapsed = eTime - sTime;

    uint num = FV * mantissaAPR * year;
    uint denom = mantissaAPR * year + APR * elapsed;

    return num / denom;
    
  }  
}

