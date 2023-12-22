// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

import "./Create2.sol";
import "./MetaProxyFactory.sol";
import "./IPoolFactory.sol";

/// @title Factory contract to deploy Derivable pool using ERC-3448.
/// @author Derivable Labs
contract PoolFactory is IPoolFactory {
    bytes32 constant internal ORACLE_MASK = bytes32((1 << 255) | type(uint160).max);

    /// @notice PoolLogic contract
    address immutable public LOGIC;

    // events
    event Derivable(
        bytes32 indexed topic1,
        bytes32 indexed topic2,
        bytes32 indexed topic3,
        bytes data
    );

    /// @param logic PoolLogic contract address
    constructor(address logic) {
        require(logic != address(0), "PoolFactory: ZERO_ADDRESS");
        LOGIC = logic;
    }

    /// deploy a new Pool using MetaProxy
    /// @param config immutable configs for the pool
    function createPool(
        Config memory config
    ) external returns (address pool) {
        bytes memory input = abi.encode(config);
        pool = MetaProxyFactory.metaProxyFromBytes(LOGIC, input);
        require(pool != address(0), "PoolFactory: CREATE2_FAILED");
        emit Derivable(
            'PoolCreated',                          // topic1: event name
            config.ORACLE & ORACLE_MASK,            // topic2: price index
            bytes32(uint256(uint160(config.TOKEN_R))), // topic3: reserve token
            abi.encode(
                config.FETCHER,
                config.ORACLE,
                config.K,
                config.MARK,
                config.INTEREST_HL,
                config.PREMIUM_HL,
                config.MATURITY,
                config.MATURITY_VEST,
                config.MATURITY_RATE,
                config.OPEN_RATE,
                uint256(uint160(pool))
            )
        );
    }
}

