// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./LiquidityManagerMock.sol";
import "./LiquidityManagerFactory.sol";

// mock class using NFTPool
contract LiquidityManagerFactoryMock is LiquidityManagerFactory {
    constructor(address _algebraFactory, address _swapRouter, address _poolDeployer)
        LiquidityManagerFactory(_algebraFactory, _swapRouter, _poolDeployer){}

    function _createLiquidityManager(address pool, address token0, address token1, address feeRecipient,
        string memory name, string memory symbol) internal override returns (address liquidityManager)
    {
        liquidityManager = address(
            new LiquidityManagerMock{salt : keccak256(abi.encodePacked(token0, token1, symbol))}(
                pool, token0, token1, feeRecipient, name, symbol, POOL_DEPLOYER, SWAP_ROUTER
            )
        );
    }
}

