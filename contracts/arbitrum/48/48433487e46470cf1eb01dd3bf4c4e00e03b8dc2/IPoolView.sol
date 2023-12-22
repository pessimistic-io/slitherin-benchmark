//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {IPool} from "./IPool.sol";

interface IPoolView {
    function maxFYTokenOut(IPool pool) external view returns (uint128);

    function maxFYTokenIn(IPool pool) external view returns (uint128);

    function maxBaseIn(IPool pool) external view returns (uint128);

    function maxBaseOut(IPool pool) external view returns (uint128);
}

