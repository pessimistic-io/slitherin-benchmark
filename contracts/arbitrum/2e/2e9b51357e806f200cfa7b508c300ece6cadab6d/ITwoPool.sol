pragma solidity ^0.5.4;

import "./IERC20.sol";


contract ITwoPool is IERC20 {

    function add_liquidity(uint[2] calldata amounts, uint min_mint_amount) external;

    function coins(uint i) external view returns (address);
}

