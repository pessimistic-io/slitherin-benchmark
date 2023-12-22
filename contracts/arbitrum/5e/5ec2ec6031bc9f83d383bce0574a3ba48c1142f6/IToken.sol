// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IToken {

    function addPair(address pair, address token) external;

    function depositLPFee(uint amount, address token) external;

    function handleFee(uint amount, address token) external;

    function getTotalFee(address _feeCheck) external view returns (uint);

}

