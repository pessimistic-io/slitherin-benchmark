//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

enum VERSION {NONE, V1, V2, V3}

library AaveDataTypes {
  struct TokenData {
    string symbol;
    address tokenAddress;
  }
}

struct TokenDataEx {
  VERSION version;
  string symbol;
  address tokenAddress;
}
