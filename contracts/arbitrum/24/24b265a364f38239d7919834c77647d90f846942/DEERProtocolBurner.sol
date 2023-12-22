// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./SafeMath.sol";

contract DEERProtocolBurner {
    using SafeMath for uint256;

    struct Burn {
        uint256 amount;
        uint256 burnedAt;
        uint256 availableBalance;
        uint256 nextBurnDate;
    }

    event TokensBurned(
        uint256 amount,
        uint256 burnedAt,
        uint256 availableBalance,
        uint256 nextBurnDate
    );

    uint256 public constant BURN_INTERVAL = 15 days;
    uint256 public constant BURN_DURATION = 30 days * 6;
    uint256 public constant PRECISION = 10 ** 18;
    uint256 public totalBurned;
    uint256 public constant INITIAL_AMOUNT = 20000 * PRECISION; // 20000 DEER
    ERC20Burnable public token;
    uint256 public balance;
    uint256 public nextBurnTime;
    uint256 public availableBalance;
    Burn[] public burns;

    constructor(address tokenAddress) {
        token = ERC20Burnable(tokenAddress);
        require(
            token.approve(address(this), type(uint256).max),
            "Approval failed"
        );
        balance = token.balanceOf(address(this));
        availableBalance = balance;
        uint256 timeSinceStart = block.timestamp % BURN_INTERVAL;
        nextBurnTime = block.timestamp.add(BURN_INTERVAL).sub(timeSinceStart);
    }

    function burn() public {
        require(availableBalance > 0, "No tokens to burn");
        require(
            block.timestamp >= nextBurnTime,
            "Burn interval has not passed yet"
        );
        require(
            block.timestamp < nextBurnTime.add(BURN_DURATION),
            "Burn duration has passed"
        );
        uint256 amount = availableBalance;
        token.burn(amount);

        totalBurned = totalBurned.add(amount);
        burns.push(
            Burn(
                amount,
                block.timestamp,
                availableBalance,
                nextBurnTime.add(BURN_INTERVAL)
            )
        );
        availableBalance = balance.sub(totalBurned);
        nextBurnTime = nextBurnTime.add(BURN_INTERVAL);
        emit TokensBurned(
            amount,
            block.timestamp,
            availableBalance,
            nextBurnTime
        );
    }

    function getBurns() public view returns (Burn[] memory) {
        return burns;
    }

    function getNextBurnTime() public view returns (uint256) {
        return nextBurnTime;
    }
}

