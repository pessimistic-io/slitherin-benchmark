// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./SafeERC20.sol";

import "./IRaffleVault.sol";
import "./ConcentratedLPVault.sol";
import "./TimeBonus.sol";

import "./console.sol";

contract RaffleVault is IRaffleVault, ConcentratedLPVault, TimeBonus {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using FixedPointMathLib for uint256;

    mapping(address => Depositor) public depositors;
    address[] public depositorList;

    uint256 public nextRaffleId;
    mapping(uint256 => Raffle) public raffles;
    mapping(uint256 => uint256) public rands; // For transparency. Random number picked for each raffle

    address private treasuryAddress;

    // =============================================================
    //                        Initialize
    // =============================================================
    // TimeBonus default: 1% per week, max 100%
    constructor(address depostiableToken_, address dexPoolAddress_, int24 initialTickLower_, int24 initialTickUpper_, address _treasuryAddress)
      ConcentratedLPVault(depostiableToken_, dexPoolAddress_, initialTickLower_, initialTickUpper_)
      TimeBonus(60 * 60 * 24 * 7 * 100, 10_000)
    {
        nextRaffleId = 1;

        uint8 decimals = ERC20(depostiableToken_).decimals();
        uint256 depositAmountLimit = (10 ** decimals).mul(100);
        setMinimumDeposit(depositAmountLimit);

        treasuryAddress = _treasuryAddress;

        _setInitialFeeCharge();
    }

    function updateTreasuryAddress(address newTreasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryAddress = newTreasuryAddress;
    }

    // Override
    function _setInitialFeeCharge() internal virtual override {
        addFeeInfo(0, Fee(FeeType.Bps, 0, 0, treasuryAddress)); // Management Fee: 0% - on rebalance (TVL)
        addFeeInfo(1, Fee(FeeType.Bps, 500, 0, treasuryAddress)); // Performance Fee: 5% - on rebalance (Fees)
        addFeeInfo(2, Fee(FeeType.Bps, 0, 0, treasuryAddress)); // Withdrawal Fee: 0% - on withdrawal (TVL)
        addFeeInfo(3, Fee(FeeType.Bps, 0, 0, treasuryAddress)); // Withdrawal Fee: 0% - on withdrawal (Fees)
        addFeeInfo(4, Fee(FeeType.Bps, 3_000, 0, treasuryAddress)); // Raffle Fee: 30% - on raffle (Fees) goes to treasury for DAO
    }

    // =============================================================
    //                  Accounting Logic
    // =============================================================
    function convertToAssets(uint256 shares) public view override returns (uint256[] memory assets) {
        // assets = liquidity, fee0, fee1
        assets = new uint256[](3);

        uint256 totalShares = totalSupply();
        if (totalShares == 0) return assets;

        uint256 proportionX96 = FullMath.mulDiv(shares, FixedPoint96.Q96, totalShares);
        uint256 totalLiquidity = uint256(pool.getTotalLiquidity());
        assets[0] = totalLiquidity.mulDivDown(proportionX96, FixedPoint96.Q96);

        // Same logic as parent, but don't calculate fees earned
        assets[1] = 0;
        assets[2] = 0;
    }

    // =============================================================
    //                    INTERNAL HOOKS LOGIC
    // =============================================================
    function _beforeDeposit(uint256 depositAmount) internal virtual override {
        super._beforeDeposit(depositAmount);

        _updateDepositorInfo(msg.sender, depositAmount);

        Depositor storage depositor = depositors[msg.sender];

        emit RaffleDeposit(
          nextRaffleId,
          raffles[nextRaffleId],
          msg.sender,
          depositor.totalDeposits,
          depositor.averageDeposits,
          depositor.bonus
        );
    }

    function _updateDepositorInfo(address userAddress, uint256 amount) internal {
        Depositor storage depositor = depositors[userAddress];

        // First deposit
        if (depositor.lastDepositTime == 0 && depositor.totalDeposits == 0 && depositor.numberOfDeposits == 0) {
          depositor.averageDeposits = amount;
          depositor.totalDeposits = amount;
          depositor.numberOfDeposits = 1;
          depositor.bonus = 0;
          depositor.lastDepositTime = block.timestamp;

          depositorList.push(userAddress);
          return;
        }

        uint256 currentTime = block.timestamp;
        uint256 deltaTime = currentTime - depositor.lastDepositTime;

        uint256 preTotalDeposits = depositor.averageDeposits.mul(depositor.numberOfDeposits);
        depositor.bonus += preTotalDeposits.mulDivDown(getBonusPercent(deltaTime), MAX_BONUS_BPS);
        depositor.averageDeposits = (preTotalDeposits + amount).div(depositor.numberOfDeposits + 1);
        depositor.totalDeposits += amount;
        depositor.numberOfDeposits++;
        depositor.lastDepositTime = block.timestamp;
    }
  
    function _beforeWithdraw(uint256 shares) internal virtual override {
        super._beforeWithdraw(shares);

        require(balanceOf(msg.sender) == shares, "Require withdraw all");

        // Clear user data
        delete depositors[msg.sender];

        // Prevent underflow from pop()
        if (depositorList.length < 1) return;

        if (depositorList[depositorList.length - 1] == msg.sender) {
          depositorList.pop();
        } else {
          for (uint256 i = 0; i < depositorList.length; i++) {
            if (depositorList[i] == msg.sender) {
              depositorList[i] = depositorList[depositorList.length - 1];
              depositorList.pop();
              break;
            }
          }
        }

        emit RaffleWithdraw(nextRaffleId, raffles[nextRaffleId], msg.sender);
    }

    // NOTE: This must be called before closing current raffle to apply time bonus.
    //       Since it loops through all users, it is not good idea to do in one tx with closeRaffle()
    function updateDepositorsTimeBonus() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < depositorList.length; i++) {
          Depositor storage depositor = depositors[depositorList[i]];

          uint256 deltaTime = currentTime - depositor.lastDepositTime;
          depositor.bonus += depositor.averageDeposits.mulDivDown(getBonusPercent(deltaTime), MAX_BONUS_BPS);
          depositor.lastDepositTime = block.timestamp;

          raffles[nextRaffleId].totalTWAB += depositor.totalDeposits + depositor.bonus;
        }
    }

    function closeRaffle() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        address winner = _randomPlayer();

        _collectPoolFees();
        (uint256 collectableFee0, uint256 collectableFee1) = collectedPoolFees();

        Raffle storage raffle = raffles[nextRaffleId];
        raffle.timestamp = block.timestamp;
        raffle.winner = winner;
        raffle.numberOfParticipants = depositorList.length;
        raffle.amount0 = collectableFee0;
        raffle.amount1 = collectableFee1;

        emit RaffleClosed(nextRaffleId, raffle, depositorList);

        // Send tokens to the winner, and charge fee.
        address[] memory tokens = pool.getTokens();
        IERC20 token0 = IERC20(tokens[0]);
        IERC20 token1 = IERC20(tokens[1]);

        uint256 token0Fee = _chargeFee(token0, 4, collectableFee0);
        token0.safeTransfer(winner, collectableFee0.sub(token0Fee));

        uint256 token1Fee = _chargeFee(token1, 4, collectableFee1);
        token1.safeTransfer(winner, collectableFee1.sub(token1Fee));
    
        nextRaffleId++;
    }

    function _randomPlayer() internal virtual returns (address) {
        // Generate a random number between 0 and totalTickets
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, raffles[nextRaffleId].totalTWAB))) %
          raffles[nextRaffleId].totalTWAB;

        // Store random number to show transpancy of raffle
        rands[nextRaffleId] = randomIndex;

        uint256 cumulativeBalance = 0;

        // Find the winner based on the random number
        for (uint256 i = 0; i < depositorList.length; i++) {
          Depositor storage depositor = depositors[depositorList[i]];
          cumulativeBalance += depositor.totalDeposits + depositor.bonus;
          if (cumulativeBalance >= randomIndex) {
            return depositorList[i];
          }
        }

        return address(0); // Should not happen. Fallback in case no winner is found.
    }

    function _hasTimeBonusAuthority() internal view virtual override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // =============================================================
    //                  Getters
    // =============================================================
    function getNumberOfDepositors() public view returns (uint256) {
        return depositorList.length;
    } 
}

