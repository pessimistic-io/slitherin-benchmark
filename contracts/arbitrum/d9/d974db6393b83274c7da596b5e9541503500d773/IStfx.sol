//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStfxStorage} from "./IStfxStorage.sol";

interface IStfx is IStfxStorage {
    event Initialized(address indexed manager, address indexed stfxAddress, address indexed vault);

    function initialize(Stf calldata _stf, address _manager, address _usdc, address _weth, address _reader) external;

    function remainingBalance() external view returns (uint256);
}

