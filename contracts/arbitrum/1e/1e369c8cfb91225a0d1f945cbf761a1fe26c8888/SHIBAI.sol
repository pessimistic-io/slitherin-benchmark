// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Erc20C09EtherPoolContract.sol";

contract SHIBAI is
Erc20C09EtherPoolContract
{
    string public constant VERSION = "SHIBAI";

    constructor(
        string[2] memory strings,
        address[7] memory addresses,
        uint256[68] memory uint256s,
        bool[25] memory bools
    ) Erc20C09EtherPoolContract(strings, addresses, uint256s, bools)
    {

    }

    function decimals()
    public
    pure
    override
    returns (uint8)
    {
        return 18;
    }
}

