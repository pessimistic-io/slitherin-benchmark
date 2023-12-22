//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IConeCamelotFactory {
    event PoolCreated(address indexed uniPool, address indexed manager, address indexed pool);

    function deployVault(
        address tokenA,
        address tokenB,
        address manager,
        uint16 managerFee,
        int24[] calldata lowerTick,
        int24[] calldata upperTick,
        uint256[] calldata percentageBIPS
    ) external returns (address pool);
}

