// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

/** amaze **/
contract HelloAuthor {
  event MessageSent(address indexed sender, string message);
  function sendMessage(string calldata newMessage) public {
    emit MessageSent(msg.sender, newMessage);
  }
}