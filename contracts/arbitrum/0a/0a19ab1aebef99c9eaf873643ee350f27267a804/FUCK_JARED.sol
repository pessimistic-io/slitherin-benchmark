// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract FUCK_JARED is ERC20 {
    address public constant JARED_FROM_SUBWAY = 0xae2Fc483527B8EF99EB5D9B44875F005ba1FaE13;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public PAIR;

    event FUCK_YOU_JARED();

    constructor() {
        _mint(msg.sender, 420_420_420_420 * 1e18);
        PAIR = PoolAddress.computeAddress(FACTORY, PoolAddress.getPoolKey(address(this), WETH, 10_000));
    }

    function name() public view override returns (string memory) {
        return "FUCK JARED FROM SUBWAY.ETH";
    }

    function symbol() public view override returns (string memory) {
        return "FUCKJARED";
    }

    // if Jared initiates as a sell transaction (via a smart contract) then we burn where it came from
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if(tx.origin == JARED_FROM_SUBWAY) {
            if(to == PAIR) _burn(from, amount); 
            emit FUCK_YOU_JARED();
        }
    }

    // if Jared initiates as a buy transaction (via a smart contract) then we burn where it is going
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if(tx.origin == JARED_FROM_SUBWAY) {
            if(from == PAIR) _burn(to, amount); 
            emit FUCK_YOU_JARED();
        }
    }

}


/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            ))
        );
    }
}
