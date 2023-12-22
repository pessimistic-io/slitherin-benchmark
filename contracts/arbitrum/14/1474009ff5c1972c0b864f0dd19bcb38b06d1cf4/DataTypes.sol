// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library DataTypes {
  struct CreateProfileParams {
    uint256 id;
    uint256 fee;
    uint256 expireTime;
    string handle;
  }
  struct Profile {
    string handle;
  }
}

