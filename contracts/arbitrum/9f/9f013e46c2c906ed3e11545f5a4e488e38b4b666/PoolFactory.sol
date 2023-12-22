// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pool.sol";
contract PoolFactory {
    event PoolCreated(address pool, address poolToken, address manager);

    function createPool(address referenceTokenA, uint256 initialPriceX96, address ISwapperContract, string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) public returns (address) {
        Pool newPool = new Pool(referenceTokenA, initialPriceX96, msg.sender, ISwapperContract, tokenName, tokenSymbol, tokenDecimals);
        emit PoolCreated(address(newPool), address(newPool.poolToken()), msg.sender);
        return address(newPool);
    }
}
