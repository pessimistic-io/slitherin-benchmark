pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IGMXRouter.sol";
import "./IGMXTracker.sol";
import "./IBeefyVault.sol";
import "./IGMXStrategy.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";
import "./IUniswapRouterV3.sol";
import "./ICapPool.sol";
import "./ICapRewards.sol";

contract CapSingleStakeStrategy is Ownable, Pausable, GasFeeThrottler {
    using SafeERC20 for IERC20;

    address public token;
    address public pool;
    address public vault;
    address public rewards;
    address public protocolTokenAddress;
    uint256 constant DIVISOR = 1 ether;
    uint256 DEV_FEE = 3 * 10 ** 17;
    uint256 STAKING_CONTRACT_FEE = 0;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantTokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 fees, uint256 amount);

    constructor(
        address _vault,
        address _pool,
        address _rewards,
        address _token
    ) {
        vault = _vault;
        pool = _pool;
        rewards = _rewards;
        token = _token;
        _giveAllowances();
    }


    function want() external view returns (address) {
        return token;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            ICapPool(pool).deposit(tokenBalance);
            emit Deposit(balanceOf());
        }
    }

    function _withdraw(uint256 _amount) internal {
        require(msg.sender == vault, "!vault");
        uint256 wantTokenBal = IERC20(token).balanceOf(address(this));

        if (wantTokenBal < _amount) {
            ICapPool(pool).withdraw(_amount - wantTokenBal);
            wantTokenBal = IERC20(token).balanceOf(address(this));
        }

        if (wantTokenBal > _amount) {
            wantTokenBal = _amount;
        }

        IERC20(token).safeTransfer(vault, wantTokenBal);
        emit Withdraw(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        _withdraw(_amount);
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        ICapRewards(rewards).collectReward();
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        if (tokenBal > 0) {
            chargeFees();
            uint256 wantTokenHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantTokenHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 devFeeAmount = IERC20(token).balanceOf(address(this)) * DEV_FEE / DIVISOR;
        uint256 protocolTokenFeeAmount = IERC20(token).balanceOf(address(this)) * STAKING_CONTRACT_FEE / DIVISOR;
        IERC20(token).safeTransfer(owner(), devFeeAmount);

        if (protocolTokenFeeAmount > 0) {
            IERC20(token).safeTransfer(protocolTokenAddress, protocolTokenFeeAmount);
        }
        emit ChargedFees(DEV_FEE, devFeeAmount + protocolTokenFeeAmount);
    }

    // calculate the total underlying 'wantToken' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'wantToken' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // it calculates how much 'wantToken' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return ICapPool(pool).getCurrencyBalance(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ICapRewards(rewards).getClaimableReward();
    }

    // native reward amount for calling harvest
    // function callReward() public view returns (uint256) {}

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setDevFee(uint fee) external onlyOwner {
        require(fee + STAKING_CONTRACT_FEE <= 5 * 10 ** 17, "fee too high");
        DEV_FEE = fee;
    }

    function setStakingFee(uint fee) external onlyOwner {
        require(fee + DEV_FEE <= 5 * 10 ** 17, "fee too high");
        STAKING_CONTRACT_FEE = fee;
    }

    function getDevFee() external view returns (uint256) {
        return DEV_FEE;
    }

    function getStakingFee() external view returns (uint256) {
        return STAKING_CONTRACT_FEE;
    }

    function setProtocolTokenAddress(address _protocolTokenAddress) external onlyOwner {
        protocolTokenAddress = _protocolTokenAddress;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyOwner {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        _harvest();
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        uint256 poolBal = balanceOfPool();
        _withdraw(poolBal);
        IERC20(token).transfer(vault, tokenBal + poolBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
        ICapRewards(rewards).collectReward();
        ICapPool(pool).withdraw(balanceOfPool());
    }

    function testPanic() public onlyOwner {
        ICapRewards(rewards).collectReward();
        ICapPool(pool).withdraw(balanceOfPool());
        IERC20(token).transfer(owner(), balanceOf());
    }

    function pause() public onlyOwner {
        _pause();
        _removeAllowances();
    }

    function unpause() external onlyOwner {
        _unpause();
        _giveAllowances();
        deposit();
    }

    function _giveAllowances() internal {
        IERC20(token).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(token).safeApprove(pool, 0);
    }
}

