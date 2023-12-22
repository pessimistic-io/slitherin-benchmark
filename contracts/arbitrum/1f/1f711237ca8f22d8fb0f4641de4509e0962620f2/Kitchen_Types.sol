//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Recipe {
  bool active;
  uint duration; // time to cook the dish
  uint expRequired;
}

struct Result {
  uint itemId;
  uint probability;
  uint32 experience;
}

struct Activity {
  uint itemId;
  uint randomId;
  uint started;
}
