// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";
import {PartnerProxy} from "./PartnerProxy.sol";
import {IVault4626} from "./IVault4626.sol";
import {IRewarderMiniChefV2} from "./IRewarderMiniChefV2.sol";

interface IJonesGlpAdapter {
    function usdc() external view returns (address);
    function vaultRouter() external view returns (address);
    function stableVault() external view returns (address);
    function depositStable(uint256, bool) external;
}

interface IJonesGlpVaultRouter {
    function EXIT_COOLDOWN() external view returns (uint256);
    function stableRewardTracker() external view returns (address);
    function rewardCompounder(address) external view returns (address);
    function withdrawSignal(address, uint256) external view returns (uint256, uint256, bool, bool);
    function stableWithdrawalSignal(uint256 amt, bool cpd) external returns (uint256);
    function cancelStableWithdrawalSignal(uint256 eph, bool cpd) external;
    function redeemStable(uint256 eph) external returns (uint256);
    function claimRewards() external returns (uint256, uint256, uint256);
}

interface IJonesGlpRewardTracker {
    function stakedAmount(address) external view returns (uint256);
}

contract StrategyJonesUsdc is Strategy {
    string public constant name = "JonesDAO jUSDC";
    IJonesGlpAdapter public immutable adapter;
    IERC20 public immutable asset;
    IVault4626 public immutable vault;
    IJonesGlpVaultRouter public immutable vaultRouter;
    IJonesGlpRewardTracker public immutable tracker;
    IVault4626 public immutable jusdc;
    PartnerProxy public immutable proxy;
    IRewarderMiniChefV2 public immutable farming;
    uint256 public reserveRatio = 1000; // 10%
    uint256 public redeemFee = 100; // 1%
    uint256 public signaledStablesEpoch = 0;

    event SetReserveRatio(uint256);
    event SetRedeemFee(uint256);

    constructor(address _strategyHelper, address _proxy, address _adapter, address _farming) Strategy(_strategyHelper) {
        proxy = PartnerProxy(payable(_proxy));
        adapter = IJonesGlpAdapter(_adapter);
        asset = IERC20(adapter.usdc());
        vault = IVault4626(adapter.stableVault());
        vaultRouter = IJonesGlpVaultRouter(adapter.vaultRouter());
        tracker = IJonesGlpRewardTracker(vaultRouter.stableRewardTracker());
        jusdc = IVault4626(vaultRouter.rewardCompounder(address(asset)));
        farming = IRewarderMiniChefV2(_farming);
    }

    function setReserveRatio(uint256 val) public auth {
        reserveRatio = val;
        emit SetReserveRatio(val);
    }

    function setRedeemFee(uint256 val) public auth {
        redeemFee = val;
        emit SetRedeemFee(val);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        return _rateWithOptions(sha, true);
    }

    function _rateWithOptions(uint256 sha, bool applyRedeemFee) internal view returns (uint256) {
        if (totalShares == 0) return 0;
        (uint256 bal,) = farming.userInfo(1, address(proxy));
        uint256 tma = jusdc.previewRedeem(bal);
        if (signaledStablesEpoch > 0) {
            (, uint256 shares,,) = vaultRouter.withdrawSignal(address(proxy), signaledStablesEpoch);
            tma += shares;
        }
        uint256 ast0 = asset.balanceOf(address(this)) * 99 / 100;
        uint256 ast1 = vault.previewRedeem(tma);
        uint256 ast = (ast0 + ast1);
        if (applyRedeemFee) ast = ast * (10000 - redeemFee) / 10000;
        uint256 val = strategyHelper.value(address(asset), ast);
        return sha * val / totalShares;
    }

    // This strategy's value is a combination of the (~10%) USDC reserves + value of the jUSDC held
    // We also don't mint jUSDC right away but keep the USDC for withdrawal
    // So to calculate the amount of shares to give we mint based on the proportion of the total USD value
    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 tma = _rateWithOptions(totalShares, false);
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(asset), amt, slp, address(this));
        uint256 val = strategyHelper.value(address(asset), bal);
        return tma == 0 ? val : val * totalShares / tma;
    }

    // Send off some of the reserve USDC, if none is available the user will have to wait for the next `redeemStable`
    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 amt = _rateWithOptions(sha, true) * (10 ** asset.decimals()) / strategyHelper.price(address(asset));
        asset.approve(address(strategyHelper), amt);
        return strategyHelper.swap(address(asset), ast, amt, slp, msg.sender);
    }

    // Here we deposit & mint jUSDC or ask to withdraw some USDC by next epoch based on the target `reserveRatio`
    // This is the only place that we interract with the adapter / router / vault for jUSDC
    // We also claim pending rewards for manual compounding
    // (automatic compounding would make the withdrawal math more trucky)
    function _earn() internal override {
        {
            address reward = farming.SUSHI();
            proxy.call(address(farming), 0, abi.encodeWithSignature("harvest(uint256,address)", 1, address(this)));
            uint256 bal = IERC20(reward).balanceOf(address(this));
            uint256 val = strategyHelper.value(reward, bal);
            if (val > 0.5e18) {
                strategyHelper.swap(reward, address(asset), bal, slippage, address(this));
            }
        }

        proxy.call(address(vaultRouter), 0, abi.encodeWithSignature("claimRewards()"));
        proxy.pull(address(asset));

        uint256 bal = asset.balanceOf(address(this));
        uint256 val = strategyHelper.value(address(asset), bal);
        uint256 tot = _rate(totalShares);
        uint256 tar = tot * reserveRatio / 10000;
        if (val > tar) {
            if (signaledStablesEpoch > 0) {
                proxy.call(
                    address(vaultRouter),
                    0,
                    abi.encodeWithSelector(
                        vaultRouter.cancelStableWithdrawalSignal.selector, signaledStablesEpoch, true
                    )
                );
                signaledStablesEpoch = 0;
            }
            uint256 amt = ((val - tar) * strategyHelper.price(address(asset)) / 1e18) * (10 ** asset.decimals()) / 1e18;
            IERC20(asset).transfer(address(proxy), amt);
            proxy.approve(address(asset), address(adapter));
            proxy.call(address(adapter), 0, abi.encodeWithSelector(adapter.depositStable.selector, amt, true));
            proxy.approve(address(jusdc), address(farming));
            proxy.call(address(farming), 0, abi.encodeWithSelector(farming.deposit.selector, 1, jusdc.balanceOf(address(proxy)), address(proxy)));
        }
        if (val < tar) {
            if (signaledStablesEpoch != 0 && block.timestamp > signaledStablesEpoch) {
                proxy.call(
                    address(vaultRouter),
                    0,
                    abi.encodeWithSelector(vaultRouter.redeemStable.selector, signaledStablesEpoch)
                );
                proxy.pull(address(asset));
                signaledStablesEpoch = 0;
            } else if (signaledStablesEpoch == 0) {
                uint256 amt = ((tar - val) * strategyHelper.price(address(asset)) / 1e18) * (10 ** asset.decimals()) / 1e18;
                uint256 shaV = vault.previewWithdraw(amt);
                uint256 sha = jusdc.previewWithdraw(shaV);
                proxy.call(address(farming), 0, abi.encodeWithSelector(farming.withdraw.selector, 1, sha, address(proxy)));
                bytes memory dat = proxy.call(
                    address(vaultRouter),
                    0,
                    abi.encodeWithSelector(vaultRouter.stableWithdrawalSignal.selector, sha, true)
                );
                signaledStablesEpoch = abi.decode(dat, (uint256));
            }
        }
    }

    function _exit(address str) internal override {
        push(IERC20(address(asset)), str, asset.balanceOf(address(this)));
        proxy.setExec(str, true);
        proxy.setExec(address(this), false);
    }

    function _move(address old) internal override {
        signaledStablesEpoch = StrategyJonesUsdc(old).signaledStablesEpoch();
    }
}

