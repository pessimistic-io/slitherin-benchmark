// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title Hop Strategy
 * @notice Investment strategy for investing assets via Hop Strategy
 */
import { IERC20, InitializableAbstractSingleStrategy } from "./InitializableAbstractSingleStrategy.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { StableMath } from "./StableMath.sol";
import { OvnMath } from "./OvnMath.sol";



import {ISingleVault} from "./ISingleVault.sol";
import {ISwapper} from "./ISwapper.sol";
import {IOracle} from "./IOracle.sol";
import {Helpers} from "./Helpers.sol";

import {ISwap} from "./ISwap.sol";
import {IRewards} from "./IRewards.sol";

import "./console.sol";

contract HopSingleStrategy is InitializableAbstractSingleStrategy {
    using StableMath for uint256;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using OvnMath for uint256;

    IERC20 public token0;
    IERC20 public vaultAsset;

    ISwapper internal swapper;
    ISingleVault internal vault;
    IOracle internal oracleRouter;

    uint256 internal decimal;
    uint256 internal vDecimal;

    uint256[] minThresholds;


    IERC20 public HOP;
    ISwap public pool;
    IRewards public rewards;
    IERC20 public lp;


    /**
     * Initializer for setting up strategy internal state. This overrides the
     * InitializableAbstractStrategy initializer as Hop strategies don't fit
     * well within that abstraction.
     @param _vaultAddress Address of Vault
     @param _rewardTokenAddresses Addresses of Reward Tokens
     @param _assets Addresses of supported asset tokens
     @param _hop_contracts Hop related contracts
     @param _essentials Essential contracts like Swapper, Oracle
     */
    function initialize(
        address _vaultAddress, // VaultProxy address
        address[] calldata _rewardTokenAddresses, 
        address[] calldata _assets, 
        address[] calldata _hop_contracts, 
        address[] calldata _essentials
    ) external onlyGovernor initializer {
        vault = ISingleVault(_vaultAddress);
        token0 = IERC20(_assets[0]);
        vaultAsset = IERC20(vault.asset());

        HOP = IERC20(_rewardTokenAddresses[0]);

        swapper = ISwapper(_essentials[0]);
        oracleRouter = IOracle(_essentials[1]);

        pool = ISwap(_hop_contracts[0]);
        rewards = IRewards(_hop_contracts[1]);
        lp = IERC20(_hop_contracts[2]);

        console.log(_assets[0]);
        decimal = Helpers.getDecimals(_assets[0]);
        vDecimal = Helpers.getDecimals(vault.asset());

        super._initialize(_vaultAddress, _rewardTokenAddresses, _assets);
        minThresholds.push(10**14);
    }

    function _deposit(
        uint256 _amount
    ) internal {
        token0.approve(address(pool), _amount);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[pool.getTokenIndex(address(token0))] = _amount;
        uint256 _minLP = pool.calculateTokenAmount(address(this), _amounts, true).subBasisPoints(200); // -2%
        pool.addLiquidity(_amounts, _minLP, block.timestamp + 600);
    }

    function deposit(uint256 _amount) external override onlyVault nonReentrant {
        _deposit(_amount);
        _stakeLP();
    }


    function _withdraw(uint256 _amount) internal {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[pool.getTokenIndex(address(token0))] = _amount;
        uint256 _lpToWithdraw = pool.calculateTokenAmount(address(this), _amounts, false);
        

        if (_lpToWithdraw.addBasisPoints(300) > lpBalance()) {
            _withdrawAll();
            return;
        } 
        _arrangeLP(_lpToWithdraw.addBasisPoints(200));
        lp.approve(address(pool), _lpToWithdraw.addBasisPoints(200));
        pool.removeLiquidityOneToken(_lpToWithdraw.addBasisPoints(200), pool.getTokenIndex(address(token0)), _amount, block.timestamp + 600);
    }

    function withdraw(address _recipient, uint256 _amount) external override onlyVaultOrGovernor nonReentrant {
        _withdraw(_amount);
        token0.safeTransfer(_recipient, _amount);
    }

    function _withdrawAll() internal {
        _arrangeLP(lpBalance());
        lp.approve(address(pool), lpBalance());
        pool.removeLiquidityOneToken(lpBalance(), pool.getTokenIndex(address(token0)), _lpToToken0(lpBalance()).subBasisPoints(200), block.timestamp + 600);
    }
    function withdrawAll() external override onlyVault nonReentrant {
        _withdrawAll();
        token0.safeTransfer(vaultAddress,token0.balanceOf(address(this)));
    }

    function lpBalance() public override view returns (uint256) {
        return lp.balanceOf(address(this)).add(stakedBalance());
    }
    function stakedBalance() public view returns (uint256) {
        return rewards.balanceOf(address(this));
    }

    function balance() public override view returns (uint256) {
        uint256 b0 = token0.balanceOf(address(this));
        if (lpBalance() > 0) {
            b0 = b0.add(_lpToToken0(lpBalance()));
        }
        return b0;
    }

    function collectRewardTokens()
        external
        onlyVault
        nonReentrant
        override
        returns (uint256)
    {
        return _collectRewards();
    }
    function _collectRewards() internal returns (uint256) {
        rewards.getReward();
        uint256 hopBalance = HOP.balanceOf(address(this));
        console.log("RewardCollection - HOP Balance: ", hopBalance);

        uint256 rewardInVaultToken = 0;
        if (hopBalance > minThresholds[0]) {
            uint256 previous = vaultAsset.balanceOf(address(this));
            HOP.approve(address(swapper), hopBalance);
            swapper.swapCommon(address(HOP), address(vaultAsset), hopBalance);
            rewardInVaultToken = vaultAsset.balanceOf(address(this)).subOrZero(previous);
            if (rewardInVaultToken > 0) {
                console.log("RewardCollection - Reward in Vault Token: ", rewardInVaultToken);
                console.log("RewardCollection - LP Before: ", lpBalance());
                _deposit(vaultAsset.balanceOf(address(this)));
                console.log("RewardCollection - LP After: ", lpBalance());

            }
        }
        return rewardInVaultToken;
    }

    function setThresholds(uint256[] calldata _minThresholds) external onlyGovernor nonReentrant {
        minThresholds = _minThresholds;
    }

    function health() external override view  returns (uint256) {
        if (lpBalance() == 0) {
            return 0;
        }
        uint256 balance0 = balance();
        if (balance0 == 0) {
            return 0;
        }
        return 100 - ((token0.balanceOf(address(this)) * 100) / balance0);
    }
    function _lpToToken0(uint256 _lp) internal view returns (uint256) {
        return pool.calculateRemoveLiquidityOneToken(address(this), _lp, pool.getTokenIndex(address(token0)));
    }
    function _stakeLP() internal {
        uint256 lpTokenBalance = lp.balanceOf(address(this));
        lp.approve(address(rewards), lpTokenBalance);
        rewards.stake(lpTokenBalance);
    }
    function _unstakeLP(uint256 _lpBalance) internal {
        if (_lpBalance == 0) {
            return;
        }
        if (_lpBalance >= lpBalance()) {
            rewards.exit();
            return;
        }
        rewards.withdraw(_lpBalance);
    }
    function _arrangeLP(uint256 _lp) internal {
        if (_lp == 0) {
            rewards.withdraw(stakedBalance());
            return;
        }
        if (_lp > lp.balanceOf(address(this))) {
            _unstakeLP(_lp.sub(lp.balanceOf(address(this))));
        }
    }
}

