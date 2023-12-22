pragma solidity ^0.8.13;

import "./UFixed18.sol";
import "./Token18.sol";
import "./Token6.sol";

/**
 * @title IReserve
 * @notice Interface for the protocol reserve
 */
interface IReserve {
    event Redeem(address indexed account, UFixed18 costAmount, UFixed18 redeemAmount);
    event Mint(address indexed account, UFixed18 mintAmount, UFixed18 costAmount);
    event Borrow(address indexed account, UFixed18 borrowAmount);
    event Repay(address indexed account, UFixed18 repayAmount);

    function redeemPrice() external view returns (UFixed18);
    function debt(address borrower) external view returns (UFixed18);
    function repay(address borrower, UFixed18 amount) external;
    function mint(UFixed18 amount) external;
    function redeem(UFixed18 amount) external;
}

