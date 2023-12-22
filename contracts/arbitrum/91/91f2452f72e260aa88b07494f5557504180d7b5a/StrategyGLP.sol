// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IGMXRouter.sol";
import "./IGMXTracker.sol";
import "./IGLPManager.sol";
import "./IBeefyVault.sol";
import "./IGMXStrategy.sol";
import "./GasFeeThrottler.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./console.sol";

contract StrategyGLP is Ownable, Pausable, GasFeeThrottler  {
    using SafeERC20 for IERC20;

    // Tokens used
    address public token;
    address public rewardToken;

    // Third party contracts
    address public minter;
    address public chef;
    address public glpRewardStorage;
    address public gmxRewardStorage;
    address public glpManager;
    address public gmxVault;
    address public vault;

    address public protocolStakingAddress;
    uint256 STAKING_CONTRACT_FEE = 0;
    uint MAX_FEE; // 0.50%
    uint DEV_FEE;
    uint DIVISOR;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 tokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 fees, uint256 amount);

    constructor(
        address _token,        // 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf (staked glp)
        address _rewardToken,  // 0x82af49447d8a07e3bd95bd0d56f35241523fbab1 (weth)
        address _minter,       // 0xb95db5b167d75e6d04227cfffa61069348d271f5 (GMX reward router v2)
        address _chef,         // 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1 (GMX reward router)
        address _vault
    ) {
        token = _token;
        rewardToken = _rewardToken;
        minter = _minter;
        chef = _chef;
        vault = _vault;
        glpRewardStorage = IGMXRouter(chef).feeGlpTracker();
        gmxRewardStorage = IGMXRouter(chef).feeGmxTracker();
        glpManager = IGMXRouter(minter).glpManager();
        _giveAllowances();
        DEV_FEE = 3 * 10 ** (ERC20(token).decimals() - 2);
        DIVISOR = 10 ** ERC20(token).decimals();
        MAX_FEE = 5 * 10 ** (ERC20(token).decimals() - 1);
    }
    
    function want() external view returns (address) {
        return token;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 tokenBal = balanceOfWant();

        if (tokenBal > _amount) {
            tokenBal = _amount;
        }

        IERC20(token).safeTransfer(vault, tokenBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        IGMXRouter(chef).compound();   // Claim and re-stake esGMX and multiplier points
        IGMXRouter(chef).claimFees();
        uint256 rewardTokenBal = IERC20(rewardToken).balanceOf(address(this));
        if (rewardTokenBal > 0) {
            chargeFees();
            uint256 before = balanceOfWant();
            mintGlp();
            uint256 tokenHarvested = balanceOfWant() - before;
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, tokenHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 devFeeAmount = IERC20(rewardToken).balanceOf(address(this)) * DEV_FEE / DIVISOR;
        console.log("devFeeAmount: %s", devFeeAmount);
        uint256 protocolTokenFeeAmount = IERC20(rewardToken).balanceOf(address(this)) * STAKING_CONTRACT_FEE / DIVISOR;
        IERC20(rewardToken).safeTransfer(owner(), devFeeAmount);

        if (protocolTokenFeeAmount > 0) {
            IERC20(token).safeTransfer(protocolStakingAddress, protocolTokenFeeAmount);
        }

        emit ChargedFees(DEV_FEE, devFeeAmount + protocolTokenFeeAmount);
    }

    // mint more GLP with the ETH earned as fees
    function mintGlp() internal {
        uint256 rewardTokenBal = IERC20(rewardToken).balanceOf(address(this));
        if (rewardTokenBal > 0) {
            IGMXRouter(minter).mintAndStakeGlp(rewardToken, rewardTokenBal, 0, 0);
        }
    }

    // calculate the total underlying 'token' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'token' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // it calculates how much 'token' the strategy has working in the farm.
    // Always zero as you don't have to stake GLP
    function balanceOfPool() public pure returns (uint256) {
        return 0;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 rewardGLP = IGMXTracker(glpRewardStorage).claimable(address(this));
        uint256 rewardGMX = IGMXTracker(gmxRewardStorage).claimable(address(this));
        return rewardGLP + rewardGMX;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setDevFee(uint fee) external onlyOwner {
        require(fee + STAKING_CONTRACT_FEE <= MAX_FEE, "fee too high");
        DEV_FEE = fee;
    }

    function setStakingFee(uint fee) external onlyOwner {
        require(fee + DEV_FEE <= MAX_FEE, "fee too high");
        STAKING_CONTRACT_FEE = fee;
    }

    function getDevFee() external view returns (uint256) {
        return DEV_FEE;
    }

    function getStakingFee() external view returns (uint256) {
        return STAKING_CONTRACT_FEE;
    }

    function setStakingAddress(address _protocolStakingAddress) external onlyOwner {
        protocolStakingAddress = _protocolStakingAddress;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyOwner {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Transfers all token, GLP, esGMX and MP to new strat.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        address stratAddress = candidate.implementation;

        IGMXRouter(chef).signalTransfer(stratAddress);
        IGMXStrategy(stratAddress).acceptTransfer();

        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(vault, tokenBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
    }

    function pause() public onlyOwner {
        _pause();
        _removeAllowances();
    }

    function unpause() external onlyOwner {
        _unpause();
        _giveAllowances();
    }

    function _giveAllowances() internal {
        console.log("glpManager", glpManager);
        console.log("rewardToken", rewardToken);
        IERC20(rewardToken).safeApprove(glpManager, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(rewardToken).safeApprove(glpManager, 0);
    }

    function acceptTransfer() external {
        address prevStrat = IBeefyVault(vault).strategy();
        require(msg.sender == prevStrat, "!prevStrat");
        IGMXRouter(chef).acceptTransfer(prevStrat);

        // send back 1 wei to complete upgrade
        IERC20(token).safeTransfer(prevStrat, 1);
    }
}

