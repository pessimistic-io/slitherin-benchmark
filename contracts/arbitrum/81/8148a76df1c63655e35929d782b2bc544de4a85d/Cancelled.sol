// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";

library UniswapV2Lib {
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303' // init code hash
            )))));
    }
}


contract Cancelled is ERC20, Owned(msg.sender) {

    address         public immutable PAIR;
    uint256         public constant  INITIAL_SUPPLY = type(uint112).max; // 5_192_296_858_534_827.628530496329220095
    bool            public           started = false;


    event CANCELLED(address indexed cancelled, address indexed canceller, uint256 amount);

    constructor(address _factory, address _weth) ERC20("Cancelled", "CANCEL", 18) {
        _mint(msg.sender, INITIAL_SUPPLY);
        PAIR = UniswapV2Lib.pairFor(_factory, address(this), _weth);
    }

    /// @notice Cancels the balance of a user, burning an equivalent amount from the caller's balance
    function cancel(address whomst, uint256 amount) external {
        require(started, "Cannot cancel before starting");
        require(whomst != PAIR, "The Uniswap pool is uncancellable");
        require(
            amount <= balanceOf[msg.sender] 
            && amount <= balanceOf[whomst], 
            "Insufficient balance to cancel"
        );
        
        _burn(msg.sender, amount);
        _burn(whomst, amount);

        emit CANCELLED(whomst, msg.sender, amount);
    }

    function start() public onlyOwner() {
        started = true;
    }

}

