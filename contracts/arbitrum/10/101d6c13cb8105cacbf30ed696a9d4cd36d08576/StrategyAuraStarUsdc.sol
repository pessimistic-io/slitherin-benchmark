// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IBalancerVault.sol";
import "./IAuraRewardPool.sol";
import "./IAuraBooster.sol";
import "./StratManagerUpgradeable.sol";
import "./DynamicFeeManager.sol";
import "./UniV3Actions.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}

contract StrategyAuraStarUsdc is StratManagerUpgradeable, DynamicFeeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant AURA_BOOSTER = 0x98Ef32edd24e2c92525E59afc4475C1242a30184;
    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 public constant POOL_ID = 30;

    bytes32 public constant BALANCER_POOL_ID =
        bytes32(0xead7e0163e3b33bf0065c9325fc8fb9b18cc82130000000000000000000004a9);

    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address public constant want = 0xEAD7e0163e3b33bF0065C9325fC8fb9B18cc8213;
    address public rewardPool;
    address[] public rewardTokens;
    uint256 public feeOnProfits;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 indexed wantHarvested, uint256 indexed tvl);
    event Deposit(uint256 indexed tvl);
    event Withdraw(uint256 indexed tvl);
    event ChargedFees(uint256 callFees, uint256 feeAmount1, uint256 feeAmount2, uint256 strategistFees);

    function initialize(address[] memory _addresses) public initializer {
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __DynamicFeeManager_init();
        __StratManager_init_unchained(_addresses[0], _addresses[1], _addresses[2], _addresses[3], _addresses[4]);

        feeOnProfits = 100;
        (, , , rewardPool, , ) = IAuraBooster(AURA_BOOSTER).poolInfo(POOL_ID);

        rewardTokens.push(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8); // BAL
        rewardTokens.push(0x1509706a6c66CA549ff0cB464de88231DDBe213B); // AURA
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal > 0) {
            IAuraBooster(AURA_BOOSTER).deposit(POOL_ID, wantBal, true);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IAuraRewardPool(rewardPool).withdrawAndUnwrap(_amount - wantBal, false);
            wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20Upgradeable(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 before = balanceOfWant();
        IAuraRewardPool(rewardPool).getReward();

        _swapRewardsToUsdc();
        uint256 _usdcBal = IERC20Upgradeable(USDC).balanceOf(address(this));

        if (_usdcBal > 0) {
            chargeFees(callFeeRecipient);
            _addLiquidity();
            uint256 wantHarvested = balanceOfWant() - before;
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToUsdc() internal {
        // swap BAL, AURA to ARB
        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 _bal = IERC20Upgradeable(rewardTokens[i]).balanceOf(address(this));

            if (_bal != 0) {
                BALANCER_VAULT.swap(
                    IBalancerVault.SingleSwap({
                        poolId: bytes32(0xbcaa6c053cab3dd73a2e898d89a4f84a180ae1ca000100000000000000000458),
                        kind: IBalancerVault.SwapKind.GIVEN_IN,
                        assetIn: rewardTokens[i],
                        assetOut: ARB,
                        amount: _bal,
                        userData: ""
                    }),
                    IBalancerVault.FundManagement(address(this), false, payable(address(this)), false),
                    0,
                    block.timestamp
                );
            }
        }

        uint256 _arbBal = IERC20Upgradeable(ARB).balanceOf(address(this));
        UniV3Actions.singleSwapV3(dystRouter, ARB, USDC, 500, address(this), _arbBal, 0);
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 generalFeeAmount = (IERC20Upgradeable(USDC).balanceOf(address(this)) * feeOnProfits) / MAX_FEE;

        uint256 callFeeAmount = (generalFeeAmount * callFee) / MAX_FEE;
        IERC20Upgradeable(USDC).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 feeAmount1 = (generalFeeAmount * fee1) / MAX_FEE;
        IERC20Upgradeable(USDC).safeTransfer(feeRecipient1, feeAmount1);

        uint256 feeAmount2 = (generalFeeAmount * fee2) / MAX_FEE;
        IERC20Upgradeable(USDC).safeTransfer(feeRecipient2, feeAmount2);

        uint256 strategistFeeAmount = (generalFeeAmount * strategistFee) / MAX_FEE;
        IERC20Upgradeable(USDC).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, feeAmount1, feeAmount2, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function _addLiquidity() internal {
        uint256 _usdcBal = IERC20Upgradeable(USDC).balanceOf(address(this));

        if (_usdcBal != 0) {
            BALANCER_VAULT.swap(
                IBalancerVault.SingleSwap({
                    poolId: bytes32(0xead7e0163e3b33bf0065c9325fc8fb9b18cc82130000000000000000000004a9),
                    kind: IBalancerVault.SwapKind.GIVEN_IN,
                    assetIn: USDC,
                    assetOut: want,
                    amount: _usdcBal,
                    userData: ""
                }),
                IBalancerVault.FundManagement(address(this), false, payable(address(this)), false),
                0,
                block.timestamp
            );
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IAuraRewardPool(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IAuraRewardPool(rewardPool).earned(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0; // multiple swap providers with no easy way to estimate native output.
    }

    function setFeeOnProfits(uint256 _feeOnProfits) external onlyOwner {
        feeOnProfits = _feeOnProfits;
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

        IAuraRewardPool(rewardPool).withdrawAndUnwrap(balanceOfPool(), false);

        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IAuraRewardPool(rewardPool).withdrawAndUnwrap(balanceOfPool(), false);
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
        IERC20Upgradeable(want).safeApprove(AURA_BOOSTER, type(uint).max);
        for (uint256 i; i < rewardTokens.length; ++i) {
            IERC20Upgradeable(rewardTokens[i]).safeApprove(address(BALANCER_VAULT), type(uint).max);
        }
        IERC20Upgradeable(USDC).safeApprove(address(BALANCER_VAULT), type(uint).max);
        IERC20Upgradeable(ARB).safeApprove(dystRouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeApprove(AURA_BOOSTER, 0);
        for (uint256 i; i < rewardTokens.length; ++i) {
            IERC20Upgradeable(rewardTokens[i]).safeApprove(address(BALANCER_VAULT), 0);
        }
        IERC20Upgradeable(USDC).safeApprove(address(BALANCER_VAULT), 0);
        IERC20Upgradeable(ARB).safeApprove(dystRouter, 0);
    }
}

