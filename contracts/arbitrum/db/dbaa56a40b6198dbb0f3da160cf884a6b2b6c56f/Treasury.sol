// SPDX-License-Identifier: GPL-3.0

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

pragma solidity 0.8.18;

contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdcToken;

    event Deposit(address depositor, uint256 amount);
    event Withdraw(address account, uint256 amount);
    event DepositEth(address depositor, uint256 amount);
    event WithdrawEth(address account, uint256 amount);
    event Recovered(address token, address account, uint256 amount);

    constructor(address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
    }

    /**
     * @notice withdraws the specified amount of USDC to the specified account
     * @param account the address to which the USDC is withdrawn
     * @param amount the amount of USDC to withdraw
     */
    /// #if_succeeds {:msg "The balance of the contract after the withdrawal is the old balance minus the amount withdrawn"} usdcToken.balanceOf(address(this)) == old(usdcToken.balanceOf(address(this))) - amount;
    function withdraw(
        address account,
        uint256 amount
    ) public onlyOwner nonReentrant {
        require(
            amount <= usdcToken.balanceOf(address(this)),
            "Amount too high"
        );
        usdcToken.safeTransfer(account, amount);
        emit Withdraw(account, amount);
    }

    /**
     * @notice deposits the specified amount of USDC to the contract
     * @param amount the amount of USDC to deposit
     */
    function deposit(uint256 amount) public nonReentrant {
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice withdraws the specified amount of ETH to the specified account
     * @param account the address to which the ETH is withdrawn
     * @param amount the amount of ETH to withdraw
     */
    function withdrawEth(
        address account,
        uint256 amount
    ) public onlyOwner nonReentrant {
        require(address(this).balance >= amount, "insufficient balance");
        require(account != address(0));
        (bool success, ) = account.call{value: amount}("");
        require(success);
        emit WithdrawEth(account, amount);
    }

    /**
     * @notice deposits the specified amount of ETH to the contract
     * @param amount the amount of ETH to deposit
     */
    function depositEth(uint256 amount) public payable nonReentrant {
        require(msg.value == amount, "Insufficient Eth");
        emit DepositEth(msg.sender, amount);
    }

    /**
     * @notice recovers the specified amount of the specified token to the specified account
     * @param tokenAddress the address of the token to recover
     * @param account the address to which the token is recovered
     * @param amount the amount of the token to recover
     */
    function recover(
        address tokenAddress,
        address account,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(tokenAddress != address(usdcToken), "USDC is not recoverable");
        IERC20(tokenAddress).safeTransfer(account, amount);
        emit Recovered(tokenAddress, account, amount);
    }

    receive() external payable {
        (bool success, ) = msg.sender.call{value: msg.value}("");
        require(success);
    }
}

