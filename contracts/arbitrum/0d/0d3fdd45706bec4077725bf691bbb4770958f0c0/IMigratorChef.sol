// File contracts/MiniChefV2.sol

pragma solidity 0.8.20;

import {IERC20} from "./IERC20.sol";

interface IMigratorChef {
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    function migrate(IERC20 token) external returns (IERC20);
}

