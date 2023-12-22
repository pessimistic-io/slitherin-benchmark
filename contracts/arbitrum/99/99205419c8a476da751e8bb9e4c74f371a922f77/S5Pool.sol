// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";

/*
 * @title S5Pool
 * @author cyfrin.io
 *
 * @notice a stablecoin focused DEX who only supports assets that are 1:1 with each other, for example DAI/USDC/USDT
 * Stablecoins are assets whose value is non-volatile in nature. 
 * On this exchange, we allow any number of token A to be swapped with token B or token C because we assume they have the same value. 
 * @notice unlike uniswap, this is a tripool, with 3 tokens instead of 2. This works because we assume all 3 tokens have the same value.
 * 
 * Invariant: Since this is a stablecoin dex, you should always be able to get the same or more tokens out than you put in.
 * For example: 
 *   - One should be able to deposit 100 tokenA, 100 tokenB, and 100 tokenC for a total of 300 tokens 
 *   - On redemption, they should get at least 300 tokens back, never less
 */
contract S5Pool is ERC20, Ownable {
    using SafeERC20 for IERC20;

    error S5Pool__DeadlinePast(uint64 deadline);
    error S5Pool__MoreThanZero(uint256 amount);
    error S5Pool__NotEnoughBalance(IERC20 token, uint256 amount);
    error S5Pool__UnknownToken(IERC20 token);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 private immutable i_tokenA;
    IERC20 private immutable i_tokenB;
    IERC20 private immutable i_tokenC;
    uint256 private constant FEE = 1; // 0.1% to LPs & to the owner
    uint256 private constant PRECISION = 1000;
    uint256 private s_totalOwnerFees;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Swapped(address indexed account, IERC20 indexed tokenFrom, IERC20 indexed tokenTo, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier revertIfDeadlinePassed(uint64 deadline) {
        if (deadline < uint64(block.timestamp)) {
            revert S5Pool__DeadlinePast(deadline);
        }
        _;
    }

    modifier revertIfZero(uint256 amount) {
        if (amount == 0) {
            revert S5Pool__MoreThanZero(amount);
        }
        _;
    }

    modifier revertIfUnknownToken(IERC20 token) {
        if (token != i_tokenA && token != i_tokenB && token != i_tokenC) {
            revert S5Pool__UnknownToken(token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(IERC20 tokenA, IERC20 tokenB, IERC20 tokenC) ERC20("S5Pool Shares", "S5PS") Ownable(msg.sender) {
        i_tokenA = tokenA;
        i_tokenB = tokenB;
        i_tokenC = tokenC;
    }

    /*
     * @notice deposit tokenA and tokenB into the pool. You must always deposit the same amount of each
     */
    function deposit(uint256 amount, uint64 deadline) external revertIfDeadlinePassed(deadline) revertIfZero(amount) {
        _mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
        i_tokenA.safeTransferFrom(msg.sender, address(this), amount);
        i_tokenB.safeTransferFrom(msg.sender, address(this), amount);
        i_tokenC.safeTransferFrom(msg.sender, address(this), amount);
    }

    /* 
     * @notice withdraw tokenA and tokenB from the pool. You must always withdraw the same amount of each
     * @dev there are no slippage parameters, which isn't great, but perhaps that won't help you...
     */
    function redeem(uint64 deadline) external revertIfDeadlinePassed(deadline) {
        uint256 amount = balanceOf(msg.sender);
        uint256 tokenAToWithdraw = (amount * i_tokenA.balanceOf(address(this))) / totalSupply();
        uint256 tokenBToWithdraw = (amount * i_tokenB.balanceOf(address(this))) / totalSupply();
        uint256 tokenCToWithdraw = (amount * i_tokenC.balanceOf(address(this))) / totalSupply();

        emit Withdrawn(msg.sender, amount);
        _burn(msg.sender, amount);

        i_tokenA.safeTransfer(msg.sender, tokenAToWithdraw);
        i_tokenB.safeTransfer(msg.sender, tokenBToWithdraw);
        i_tokenC.safeTransfer(msg.sender, tokenCToWithdraw);
    }

    /* 
     * @notice swap tokenA for tokenB or vice versa.
     * @dev swapping has a 0.03% fee for LPs
     */
    function swapFrom(IERC20 tokenFrom, IERC20 tokenTo, uint256 amount)
        external
        revertIfUnknownToken(tokenFrom)
        revertIfUnknownToken(tokenTo)
    {
        // Checks
        if (tokenTo.balanceOf(address(this)) < amount) {
            revert S5Pool__NotEnoughBalance(tokenTo, amount);
        }

        // Effects
        // LP fees
        uint256 lpFee = calculateFee(amount);
        // Owner fees
        uint256 ownerFee = calculateFee(amount);
        s_totalOwnerFees = s_totalOwnerFees + ownerFee;
        uint256 amountMinusFee = amount - (lpFee + ownerFee);
        emit Swapped(msg.sender, tokenFrom, tokenTo, amountMinusFee);

        // Interactions
        tokenFrom.safeTransferFrom(msg.sender, address(this), amountMinusFee);
        tokenTo.safeTransfer(msg.sender, amountMinusFee);
    }

    /*
     * @dev users can pick any of the stablecoins to take their fee in
     */
    function collectOwnerFees(IERC20 token) external revertIfUnknownToken(token) {
        uint256 amount = s_totalOwnerFees;
        s_totalOwnerFees = 0;
        i_tokenA.safeTransfer(owner(), amount);
    }

    function calculateFee(uint256 amount) public pure returns (uint256) {
        return (amount * FEE) / PRECISION;
    }
}

