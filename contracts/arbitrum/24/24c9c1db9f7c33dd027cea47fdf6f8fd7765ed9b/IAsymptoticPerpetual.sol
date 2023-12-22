// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

struct Config {
    address TOKEN;
    address TOKEN_R;
    bytes32 ORACLE;
    uint K;
    uint MARK;
    uint INIT_TIME; // TODO: change to uint32
    uint HALF_LIFE; // TODO: change to uint32
}

struct Market {
    uint xkA;
    uint xkB;
}

struct State {
    uint R;
    uint a;
    uint b;
}

interface IAsymptoticPerpetual {
    function init(
        Config memory config,
        uint a,
        uint b
    ) external returns (uint rA, uint rB, uint rC);

    /**
     * @param payload passed to Helper.swapToState callback, should not used by this function
     */
    function swap(
        Config calldata config,
        uint sideIn,
        uint sideOut,
        address helper,
        bytes calldata payload
    ) external returns(uint amountIn, uint amountOut);
}

