// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";
import {PartnerProxy} from "./PartnerProxy.sol";
import {IVault4626} from "./IVault4626.sol";

interface IJonesGlpAdapter {
    function usdc() external view returns (address);
    function vaultRouter() external view returns (address);
    function stableVault() external view returns (address);
    function depositStable(uint256, bool) external;
}

interface IJonesGlpVaultRouter {
    function EXIT_COOLDOWN() external view returns (uint256);
    function stableRewardTracker() external view returns (address);
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
    IJonesGlpAdapter public adapter;
    IERC20 public asset;
    IVault4626 public vault;
    IJonesGlpVaultRouter public vaultRouter;
    IJonesGlpRewardTracker public tracker;
    PartnerProxy public proxy;
    uint256 public reserveRatio = 1000; // 10%
    uint256 public redeemFee = 100; // 1%
    uint256 public signaledStablesEpoch = 0;

    event SetReserveRatio(uint256);
    event SetRedeemFee(uint256);

    constructor(address _strategyHelper, address _proxy, address _adapter) Strategy(_strategyHelper) {
        proxy = PartnerProxy(_proxy);
        adapter = IJonesGlpAdapter(_adapter);
        asset = IERC20(adapter.usdc());
        vault = IVault4626(adapter.stableVault());
        vaultRouter = IJonesGlpVaultRouter(adapter.vaultRouter());
        tracker = IJonesGlpRewardTracker(vaultRouter.stableRewardTracker());
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
        uint256 tma = tracker.stakedAmount(address(proxy));
        if (signaledStablesEpoch > 0) {
            (, uint256 shares,,) = vaultRouter.withdrawSignal(address(proxy), signaledStablesEpoch);
            tma += shares;
        }
        uint256 ast0 = asset.balanceOf(address(this));
        uint256 ast1 = vault.previewRedeem(tma) * (10000 - redeemFee) / 10000;
        uint256 val = strategyHelper.value(address(asset), ast0+ast1);
        return sha * val / totalShares;
    }

    // This strategy's value is a combination of the (~10%) USDC reserves + value of the jUSDC held
    // We also don't mint jUSDC right away but keep the USDC for withdrawal
    // So to calculate the amount of shares to give we mint based on the proportion of the total USD value
    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 tma = rate(totalShares);
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(asset), amt, slp, address(this));
        uint256 val = strategyHelper.value(address(asset), bal);
        return tma == 0 ? val : val * totalShares / tma;
    }

    // Send off some of the reserve USDC, if none is available the user will have to wait for the next `redeemStable`
    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 amt = _rate(sha) * (10 ** asset.decimals()) / 1e18;
        asset.approve(address(strategyHelper), amt);
        return strategyHelper.swap(address(asset), ast, amt, slp, msg.sender);
    }

    // Here we deposit & mint jUSDC or ask to withdraw some USDC by next epoch based on the target `reserveRatio`
    // This is the only place that we interract with the adapter / router / vault for jUSDC
    // We also claim pending rewards for manual compounding
    // (automatic compounding would make the withdrawal math more trucky)
    function _earn() internal override {
        proxy.call(address(vaultRouter), 0, abi.encodeWithSignature("claimRewards()"));
        proxy.pull(address(asset));
        uint256 bal = asset.balanceOf(address(this)) * 1e18 / (10 ** asset.decimals());
        uint256 tot = _rate(totalShares);
        uint256 tar = tot * reserveRatio / 10000;
        if (bal > tar) {
            if (signaledStablesEpoch > 0) {
                proxy.call(address(vaultRouter), 0, abi.encodeWithSelector(vaultRouter.cancelStableWithdrawalSignal.selector, signaledStablesEpoch, false));
                signaledStablesEpoch = 0;
            }
            uint256 amt = (bal-tar) * (10 ** asset.decimals()) / 1e18;
            IERC20(asset).transfer(address(proxy), amt);
            proxy.approve(address(asset), address(adapter));
            proxy.call(address(adapter), 0, abi.encodeWithSelector(adapter.depositStable.selector, amt, false));
        }
        if (bal < tar) {
            if (signaledStablesEpoch > block.timestamp) {
                proxy.call(address(vaultRouter), 0, abi.encodeWithSelector(vaultRouter.redeemStable.selector, signaledStablesEpoch));
                proxy.pull(address(asset));
                signaledStablesEpoch = 0;
            }
            if (signaledStablesEpoch == 0) {
                uint256 amt = (tar-bal) * (10 ** asset.decimals()) / 1e18;
                uint256 sha = vault.previewWithdraw(amt);
                bytes memory dat = proxy.call(address(vaultRouter), 0, abi.encodeWithSelector(vaultRouter.stableWithdrawalSignal.selector, sha, false));
                signaledStablesEpoch = abi.decode(dat, (uint256)); 
            }
        }
    }

    function _exit(address str) internal override {
        push(IERC20(address(asset)), str, asset.balanceOf(address(this)));
        proxy.setExec(str, true);
        proxy.setExec(address(this), false);
    }

    function _move(address) internal override {
        // can only earn once whitelisted, let it happen post move
    }
}

