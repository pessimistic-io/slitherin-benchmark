// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface IMinter {
  struct DeployParams {
    string name;
    string symbol;
    address depositToken;
    uint minInvestmentAmount;
  }
}

