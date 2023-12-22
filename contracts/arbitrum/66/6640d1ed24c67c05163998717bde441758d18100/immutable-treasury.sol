// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./immutable-token.sol";

contract ImmutableTreasury is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    ImutableToken public token;
    address public killSwitch;
    address public liquidityPoolAddress;
    uint256 public liquidityPoolDividendPercentage;

    uint256 public totalDividends;
    uint256 public unclaimedDividends;
    uint256 public dividendsClaimDeadline;

    mapping(address => uint256) public lastDividendsClaimed;

    event DividendsDeposited(uint256 amount);
    event DividendsWithdrawn(uint256 amount);
    event DividendsClaimed(address indexed account, uint256 amount);

    constructor(
        ImutableToken _token,
        address _killSwitch,
        address _liquidityPoolAddress,
        uint256 _liquidityPoolDividendPercentage
    ) {
        token = _token;
        killSwitch = _killSwitch;
        liquidityPoolAddress = _liquidityPoolAddress;
        liquidityPoolDividendPercentage = _liquidityPoolDividendPercentage;
    }

    receive() external payable {
        totalDividends = totalDividends.add(msg.value);
        unclaimedDividends = unclaimedDividends.add(msg.value);
        emit DividendsDeposited(msg.value);
    }

    function dividendsOwing(address account) public view returns (uint256) {
        uint256 newDividends = totalDividends.sub(
            lastDividendsClaimed[account]
        );
        uint256 tokenBalance = token.balanceOf(account);
        uint256 totalTokenSupply = token.totalSupply();

        return tokenBalance.mul(newDividends).div(totalTokenSupply);
    }

    function claimDividends() external nonReentrant whenNotPaused {
        require(
            block.timestamp <= dividendsClaimDeadline,
            "Dividend claim deadline has passed"
        );

        uint256 owing = dividendsOwing(msg.sender);
        require(owing > 0, "No dividends to claim");

        lastDividendsClaimed[msg.sender] = totalDividends;
        unclaimedDividends = unclaimedDividends.sub(owing);
        payable(msg.sender).transfer(owing);

        emit DividendsClaimed(msg.sender, owing);
    }

    function withdrawUnclaimedDividends() external onlyOwner nonReentrant {
        require(
            block.timestamp > dividendsClaimDeadline,
            "Dividend claim period is still active"
        );

        uint256 amount = unclaimedDividends;
        unclaimedDividends = 0;
        payable(owner()).transfer(amount);

        emit DividendsWithdrawn(amount);
    }

    function setLiquidityPoolDividendPercentage(
        uint256 newPercentage
    ) external onlyOwner {
        require(newPercentage <= 100, "Percentage must be between 0 and 100");
        liquidityPoolDividendPercentage = newPercentage;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
        uint256 newDeadline = block.timestamp.add(1 days);
        dividendsClaimDeadline = newDeadline;
        uint256 lpDividends = calculateLiquidityPoolDividends();
        require(
            lpDividends <= unclaimedDividends,
            "Not enough unclaimed dividends to transfer to liquidity pool"
        );

        lastDividendsClaimed[liquidityPoolAddress] = totalDividends;
        unclaimedDividends = unclaimedDividends.sub(lpDividends);
        payable(liquidityPoolAddress).transfer(lpDividends);
    }

    function calculateLiquidityPoolDividends() private view returns (uint256) {
        uint256 newDividends = totalDividends.sub(
            lastDividendsClaimed[liquidityPoolAddress]
        );
        uint256 tokenBalance = token.balanceOf(liquidityPoolAddress);
        uint256 totalTokenSupply = token.totalSupply();
        uint256 lpDividends = tokenBalance.mul(newDividends).div(
            totalTokenSupply
        );

        return lpDividends.mul(liquidityPoolDividendPercentage).div(100);
    }

    function setKillSwitch(address newKillSwitch) external {
        require(
            msg.sender == killSwitch,
            "Only the kill switch can change the kill switch address"
        );
        killSwitch = newKillSwitch;
    }

    function executeKillSwitch() external {
        require(
            msg.sender == killSwitch,
            "Only the kill switch can execute the kill switch"
        );
        selfdestruct(payable(killSwitch));
    }
}

