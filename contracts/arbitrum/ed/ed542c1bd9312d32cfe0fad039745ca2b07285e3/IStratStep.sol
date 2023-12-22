// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IStratStep {

    struct OracleResponse {
        address vault;
        address[] tokens;
        uint256[] tokensAmount;
    }


    function enter(bytes memory parameters) external;
    function exit(bytes memory parameters) external;

    function oracleEnter(OracleResponse memory previous, bytes memory parameters) external view returns (OracleResponse memory);
    function oracleExit(OracleResponse memory previous, bytes memory parameters) external view returns (OracleResponse memory);
}
