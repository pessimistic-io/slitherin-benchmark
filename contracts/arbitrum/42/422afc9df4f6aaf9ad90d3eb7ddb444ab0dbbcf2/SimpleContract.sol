// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract SimpleContract {

    event LogMessage(string message);

    function logMsg(string memory _message) public {
        emit LogMessage(_message);
    }

}