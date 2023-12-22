// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IBeefySwapper} from "./IBeefySwapper.sol";
import "./StratFeeManagerInitializable.sol";

interface ISilo {
    function deposit(address asset, uint amount, bool collateralOnly) external;
    function withdraw(address asset, uint amount, bool collateralOnly) external;
    function balanceOf(address user) external view returns (uint256);
}

interface ISiloCollateralToken {
    function asset() external view returns (address);
}

interface ISiloLens {
    function balanceOfUnderlying(uint256 _assetTotalDeposits, address _shareToken, address _user) external view returns (uint256);
    function totalDepositsWithInterest(address _silo, address _asset) external view returns (uint256 _totalDeposits);
}

interface ISiloRewards {
    function claimRewardsToSelf(address[] memory assets, uint256 amount) external;
}

contract StrategySilo is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant output = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public want;
    address public silo;
    address public collateralToken;
    address[] public rewardsClaim;
    ISiloRewards public constant rewards = ISiloRewards(0xd592F705bDC8C1B439Bd4D665Ed99C4FaAd5A680);
    ISiloLens public constant siloLens = ISiloLens(0xBDb843c7a7e48Dc543424474d7Aa63b61B5D9536);
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _collateralToken,
        address _silo,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        collateralToken = _collateralToken;
        silo = _silo;
        want = ISiloCollateralToken(collateralToken).asset();

        rewardsClaim.push(collateralToken);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 bal = balanceOfWant();

        if (bal > 0) {
            ISilo(silo).deposit(want, bal, false);
            emit Deposit(balanceOf());
        }
    }

    // Withdraws funds and sends them back to the vault
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint256 toWithdraw = _amount - wantBal;
            ISilo(silo).withdraw(want, toWithdraw, false);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = _amount * withdrawalFee / WITHDRAWAL_MAX;
            _amount = _amount - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, _amount);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    /**
     * Harvest farm tokens and convert to want tokens.
     */
    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        rewards.claimRewardsToSelf(rewardsClaim, type(uint).max);
        uint256 bal = IERC20(output).balanceOf(address(this));
        if (bal > 0) {
            swapRewardsToNative();
            chargeFees(callFeeRecipient);
            swapToWant();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        uint bal = IERC20(output).balanceOf(address(this));
        if (bal > 0) {
            IBeefySwapper(unirouter).swap(output, native, bal);
        }
         
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function swapToWant() internal {
        uint256 bal = IERC20(native).balanceOf(address(this));
        if (want != native) {
            IBeefySwapper(unirouter).swap(native, want, bal);
        }
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
        uint256 totalDeposits = siloLens.totalDepositsWithInterest(silo, want);
        return siloLens.balanceOfUnderlying(totalDeposits, collateralToken, address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 amount = balanceOfPool();
        if (amount > 0) {
            ISilo(silo).withdraw(want, balanceOfPool(), false);
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        uint256 amount = balanceOfPool();
        if (amount > 0) {
            ISilo(silo).withdraw(want, balanceOfPool(), false);
        }
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
        IERC20(output).approve(unirouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(want).approve(silo, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(output).approve(unirouter, 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(want).approve(silo, 0);
    }
}
