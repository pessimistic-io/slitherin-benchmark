// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IERC20} from "./IERC20.sol";

interface IConeCamelotVaultStorage {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _pool,
        uint16 _managerFeeBPS,
        int24[] calldata _lowerTick,
        int24[] calldata _upperTick,
        address _manager_,
        uint256[] calldata _percentageBIPS
    ) external;

    function pool() external view returns (IAlgebraPool);

    function coneFeeBPS() external view returns (uint256);

    function managerFeeBPS() external view returns (uint256);

    function managerBalance0() external view returns (uint256);

    function managerBalance1() external view returns (uint256);

    function coneBalance0() external view returns (uint256);

    function coneBalance1() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function lowerTicks(uint8) external view returns (int24);

    function upperTicks(uint8) external view returns (int24);

    function getUnderlyingBalances(uint8 _rangeType) external view returns (uint256, uint256);

    function gelatoSlippageInterval() external view returns (uint16);

    function gelatoSlippageBPS() external view returns (uint16);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function tokensForRange(uint8 _rangeType) external view returns (uint256);
}

