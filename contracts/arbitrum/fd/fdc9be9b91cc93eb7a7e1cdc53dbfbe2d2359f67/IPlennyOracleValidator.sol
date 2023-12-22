// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyOracleValidator {

    function oracleValidations(uint256, address) external view returns (uint256);

}
