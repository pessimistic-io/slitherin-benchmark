// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract DTLaunchPad is Ownable {
    using SafeMath for uint256;
    uint256 private constant USDC_DECIMAL = 10 ** 6; // target USDC
    uint256 private constant TARGET_USDC = 1000000; // target USDC
    uint256 private constant TOTAL_DISTRIBUTION = 100;
    uint256 private constant A_PERCENTAGE = 50; // 50% Liquidity Pool
    uint256 private constant B_PERCENTAGE = 35; // 35% Liquidity Vault
    uint256 private constant C_PERCENTAGE = 15; // 15% Team Development

    address private constant USDC_ADDRESS =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC token contract address

    address private constant WALLET_A =
        0xeA069B5d627deE8E0881E50600b38eCB9D3c6f9E; // Liquidity Pool address
    address private constant WALLET_B =
        0x99142456720DE2BAd95d7a3FB853b28d1947EB18; // Liquidity Vault address
    address private constant WALLET_C =
        0xA8F6a9717311943ec0cb1634b440D20470057b27; // Team Development address

    uint256 public totalDeposited; // Total deposited USDC

    mapping(address => uint256) public depositedAmounts; // participant's deposited amount
    event depositEvent(
        uint256 amountToA,
        uint256 usdc_amount,
        uint256 A_PERCENTAGE
    );
    event distributeBalanceEvent(uint256 balance, uint256 result);
    event distributeBalanceToWalletEvent(
        uint256 wallet1Amount,
        uint256 A_PERCENTAGE,
        uint256 contractBalanceMulPercentage,
        uint256 result
    );

    function deposit(uint256 amount) external {
        require(amount >= 10, "Amount must be greater than 10");
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 usdc_amount = amount * USDC_DECIMAL;
        require(
            usdc.transferFrom(msg.sender, address(this), usdc_amount),
            "USDCDistribution: Transfer failed"
        );
        totalDeposited = totalDeposited.add(usdc_amount);

        depositedAmounts[msg.sender] = depositedAmounts[msg.sender].add(
            usdc_amount
        );
        uint256 amountToA = (usdc_amount * A_PERCENTAGE) / TOTAL_DISTRIBUTION;
        uint256 amountToB = (usdc_amount * B_PERCENTAGE) / TOTAL_DISTRIBUTION;
        uint256 amountToC = (usdc_amount * C_PERCENTAGE) / TOTAL_DISTRIBUTION;
        emit depositEvent(amountToA, usdc_amount, A_PERCENTAGE);

        require(
            usdc.transfer(WALLET_A, amountToA),
            "USDCDistribution: Transfer to Wallet A failed"
        );
        require(
            usdc.transfer(WALLET_B, amountToB),
            "USDCDistribution: Transfer to Wallet B failed"
        );
        require(
            usdc.transfer(WALLET_C, amountToC),
            "USDCDistribution: Transfer to Wallet C failed"
        );
    }

    function getTotalDeposited() external view returns (uint256) {
        return totalDeposited;
    }

    function getDepositedAmount(address account) public view returns (uint256) {
        return depositedAmounts[account];
    }

    function getContractBalance() public view returns (uint256) {
        return IERC20(USDC_ADDRESS).balanceOf(address(this)) / USDC_DECIMAL;
    }

    function distributeBalance() public onlyOwner {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balance = usdc.balanceOf(address(this));
        emit distributeBalanceEvent(balance, balance / USDC_DECIMAL);

        require(balance / USDC_DECIMAL > 0, "Contract balance is zero");
        uint256 contractBalance = balance;
        uint256 wallet1Amount = contractBalance.mul(A_PERCENTAGE) /
            TOTAL_DISTRIBUTION;
        uint256 wallet2Amount = contractBalance.mul(B_PERCENTAGE) /
            TOTAL_DISTRIBUTION;
        uint256 wallet3Amount = contractBalance.mul(C_PERCENTAGE) /
            TOTAL_DISTRIBUTION;
        emit distributeBalanceToWalletEvent(
            wallet1Amount,
            A_PERCENTAGE,
            contractBalance.mul(A_PERCENTAGE),
            contractBalance.mul(A_PERCENTAGE) / TOTAL_DISTRIBUTION
        );
        require(usdc.transfer(WALLET_A, wallet1Amount), "USDC transfer failed");
        require(usdc.transfer(WALLET_B, wallet2Amount), "USDC transfer failed");
        require(usdc.transfer(WALLET_C, wallet3Amount), "USDC transfer failed");
    }

    // incase above function fail
    function withdrawUSDC() public onlyOwner {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        require(usdc.transfer(owner(), balance), "USDC withdrawal failed");
    }
}

