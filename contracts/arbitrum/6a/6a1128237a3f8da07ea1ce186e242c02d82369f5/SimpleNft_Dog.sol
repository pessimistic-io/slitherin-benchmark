// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./SimpleNftContract.sol";

contract SimpleNft_Dog is
SimpleNftContract
{
    string public constant VERSION = "SimpleNft_Dog";

    constructor(
        string[3] memory strings
    ) SimpleNftContract(strings)
    {

    }
}

