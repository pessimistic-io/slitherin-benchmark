// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./SwapManagerEth.sol";

contract SwapManagerGas {
    bool public store;
    // solhint-disable-next-line
    SwapManagerEth private immutable SwpMgr;

    constructor() {
        SwpMgr = new SwapManagerEth();
    }

    function bofi(
        address _from,
        address _to,
        uint256 _amountIn
    ) external {
        SwpMgr.bestOutputFixedInput(_from, _to, _amountIn);
        store = true;
    }

    function bpfi(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _i
    ) external {
        SwpMgr.bestPathFixedInput(_from, _to, _amountIn, _i);
        store = true;
    }

    function bifo(
        address _from,
        address _to,
        uint256 _amountOut
    ) external {
        SwpMgr.bestInputFixedOutput(_from, _to, _amountOut);
        store = true;
    }

    function bpfo(
        address _from,
        address _to,
        uint256 _amountOut,
        uint256 _i
    ) external {
        SwpMgr.bestPathFixedOutput(_from, _to, _amountOut, _i);
        store = true;
    }
}

