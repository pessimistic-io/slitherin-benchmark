// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMasterOfCoin {

    // Gives the token to the stream. Stream in our case will be the atlas mine.
    function grantTokenToStream(address _stream, uint256 _amount) external;
}
