// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";

import "./IGMXRouter.sol";
import "./IGMXTracker.sol";
import "./IGLPManager.sol";
import "./IGMXVault.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";

contract StrategyGLP is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public native;
    address public glp;

    // Third party contracts
    address public chef;
    address public glpRewardStorage;
    address public gmxRewardStorage;
    address public glpManager;
    address public gmxVault;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool public cooldown;
    uint256 public extraCooldownDuration = 900;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _chef,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        native = _want;
        chef = _chef;
        glp = IGMXRouter(chef).glp();
        glpRewardStorage = IGMXRouter(chef).feeGlpTracker();
        gmxRewardStorage = IGMXRouter(chef).feeGmxTracker();
        glpManager = IGMXRouter(chef).glpManager();
        gmxVault = IGLPManager(glpManager).vault();

        _giveAllowances();
    }

    // prevent griefing by preventing deposits for longer than the cooldown period
    modifier whenNotCooling {
        if (cooldown) {
            require(block.timestamp >= IGLPManager(glpManager).lastAddedAt(address(this))
                + IGLPManager(glpManager).cooldownDuration() 
                + extraCooldownDuration,
                "cooldown"
            );
            _;
        }
    }

    // puts the funds to work
    function deposit() public whenNotPaused whenNotCooling {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IGMXRouter(chef).mintAndStakeGlp(want, wantBal, 0, 0);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IGMXRouter(chef).unstakeAndRedeemGlp(want, ethForGlp(_amount - wantBal), 1, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IGMXRouter(chef).compound();   // Claim and restake esGMX and multiplier points
        IGMXRouter(chef).claimFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        uint256 glpAmount = IGMXTracker(glpRewardStorage).stakedAmounts(address(this));
        return glpForEth(glpAmount);
    }

    // it calculates the amount received for swapping GLP to ETH, not taking fees into account
    function glpForEth(uint256 _amount) internal view returns (uint256) {
        uint256 aumInUsdg = IGLPManager(glpManager).getAumInUsdg(false);
        uint256 glpSupply = IERC20(glp).totalSupply();
        uint256 usdgAmount = _amount * aumInUsdg / glpSupply;
        return IGMXVault(gmxVault).getRedemptionRate(want, usdgAmount);
    }

    // it calculates the amount received for swapping ETH to GLP, not taking fees into account
    function ethForGlp(uint256 _amount) internal view returns (uint256) {
        uint256 usdgAmount = _amount
            * IGMXVault(gmxVault).getMaxPrice(want)
            / IGMXVault(gmxVault).PRICE_PRECISION();
        uint256 glpSupply = IERC20(glp).totalSupply();
        uint256 aumInUsdg = IGLPManager(glpManager).getAumInUsdg(false);
        return usdgAmount * glpSupply / aumInUsdg;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 rewardGLP = IGMXTracker(glpRewardStorage).claimable(address(this));
        uint256 rewardGMX = IGMXTracker(gmxRewardStorage).claimable(address(this));
        return rewardGLP + rewardGMX;
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = rewardsAvailable();

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 glpAmount = IGMXTracker(glpRewardStorage).stakedAmounts(address(this));
        if (glpAmount > 0) {
            IGMXRouter(chef).unstakeAndRedeemGlp(want, glpAmount, 1, address(this));
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        uint256 glpAmount = IGMXTracker(glpRewardStorage).stakedAmounts(address(this));
        IGMXRouter(chef).unstakeAndRedeemGlp(want, glpAmount, 1, address(this));
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(native).safeApprove(glpManager, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(glpManager, 0);
    }

    function depositFee() public override view returns (uint256) {
        return _getMintBurnFees(true);
    }

    function withdrawFee() public override view returns (uint256) {
        return paused() ? 0 : _getMintBurnFees(false);
    }

    // fetch fees from the GMX vault for burning/minting a small amount of GLP
    function _getMintBurnFees(bool isMint) internal view returns (uint256) {
        uint256 mintBurnFee = IGMXVault(gmxVault).mintBurnFeeBasisPoints();
        uint256 taxFee = IGMXVault(gmxVault).taxBasisPoints();
        return IGMXVault(gmxVault).getFeeBasisPoints(want, 10000, mintBurnFee, taxFee, isMint);
    }

    function setCooldown(bool _cooldown) external onlyManager {
        cooldown = _cooldown;
    }

    function setExtraCooldownDuration(uint256 _extraCooldownDuration) external onlyManager {
        extraCooldownDuration = _extraCooldownDuration;
    }
}

