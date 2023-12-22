// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "./ERC20.sol";

interface ISFDistributor {
    function distribute() external;
}

contract SFDResolver {
    address public sfDistributor;
    ERC20 public tokenX;

    constructor(address _sfDistributor, ERC20 _tokenX) {
        sfDistributor = _sfDistributor;
        tokenX = _tokenX;
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        uint256 amountToDistribute = tokenX.balanceOf(sfDistributor);
        canExec = amountToDistribute > (1000 * tokenX.decimals());

        execPayload = abi.encodeCall(ISFDistributor.distribute, ());
    }
}

