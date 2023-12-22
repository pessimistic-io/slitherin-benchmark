//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./console.sol";

import {ERC20Wrapper} from "./ERC20Wrapper.sol";
import {ERC20, IERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {wToken} from "./wToken.sol";

import {DividendDistributor} from "./DividendDistributor.sol";

import {RewardRouterV2} from "./RewardRouterV2.sol";

import {Ownable} from "./Ownable.sol";

import {IVester} from "./IVester.sol";

contract wGMX is ERC20, ERC20Wrapper, Ownable {
    using SafeERC20 for IERC20;
    using DividendDistributor for DividendDistributor.Distributor;

    RewardRouterV2 public rewardRouterV2;
    IVester public immutable vester;

    IERC20 public immutable sGMX;
    IERC20 public immutable esGMX;

    DividendDistributor.Distributor public sGMXTracker;
    DividendDistributor.Distributor public sETHTracker;
    DividendDistributor.Distributor public vGMXTracker;

    wToken public immutable wsGMX;
    wToken public immutable wesGMX;
    wToken public immutable swesGMX;
    wToken public immutable vwesGMX;

    ERC20Wrapper public immutable weth;

    constructor(address _rewardRouter, address _gmx) ERC20("Wrapped GMX","wGMX") ERC20Wrapper(IERC20(_gmx)) {
        rewardRouterV2 = RewardRouterV2(_rewardRouter);
        vester = IVester(rewardRouterV2.gmxVester());
        sGMX = IERC20(rewardRouterV2.stakedGmxTracker());
        esGMX = IERC20(rewardRouterV2.esGmx());

        wsGMX = new wToken("Wrapped Staked GMX", "wsGMX");
        wesGMX = new wToken("Wrapped Escrowed GMX", "wesGMX");
        swesGMX = new wToken("Staked Wrapped Escrowed GMX", "swesGMX");
        vwesGMX = new wToken("Vested Wrapped Escrowed GMX", "vwesGMX");

        weth = ERC20Wrapper(rewardRouterV2.weth());

        sGMXTracker.setTokenReward(address(swesGMX));
        sETHTracker.setTokenReward(rewardRouterV2.weth());
        vGMXTracker.setTokenReward(address(this));
    }

    function handleRewards() external {
        uint balanceEsGMX = esGMX.balanceOf(address(this));
        uint balanceEth = weth.balanceOf(address(this));
        uint balanceGmx = underlying.balanceOf(address(this));
        rewardRouterV2.handleRewards(true, false, true, false, true, true, false);
        uint receivedEsGMX = esGMX.balanceOf(address(this)) - balanceEsGMX;
        uint receivedEth = weth.balanceOf(address(this)) - balanceEth;
        uint receivedGmx = underlying.balanceOf(address(this)) - balanceGmx;
        if(receivedEsGMX > 0) {
            _distributeEsGMX(receivedEsGMX);
            rewardRouterV2.stakeEsGmx(receivedEsGMX);
        }
        if(receivedGmx > 0) {
            _stakeGmx(address(this), receivedGmx);
            _distributeGMX(receivedGmx);
        }
        _distributeETH(receivedEth);
    }

    function withdrawTo(address account, uint256 amount) public override returns (bool) {
        _burn(_msgSender(), amount);
        uint balance = underlying.balanceOf(address(this));
        if(balance < amount) {
            uint diff = amount - balance;
            _unstakeGmx(address(this), diff);
        }
        SafeERC20.safeTransfer(underlying, account, amount);
        return true;
    }

    function deposit(uint _amount) external {
        _deposit(msg.sender, _amount);
    }

    function withdraw(uint _amount) external {
        _withdraw(msg.sender, _amount);
    }

    function fastStake(uint _amount) external {
        depositFor(msg.sender, _amount);
        _stakeGmx(msg.sender, _amount);
    }

    function stakeGmx(uint _amount) external {
        _stakeGmx(msg.sender, _amount);
    }

    function unstakeGmx(uint _amount) external {
        _unstakeGmx(msg.sender, _amount);
    }

    function stakeEsGmx(uint _amount) external {
        _stakeEsGmx(msg.sender, _amount);
    }

    function unstakeEsGmx(uint _amount) external {
        _unstakeEsGmx(msg.sender, _amount);
    }

    function claimableEsGMX(address account) public view returns(uint) {
        return sGMXTracker.withdrawable(account, wsGMX.balanceOf(account) + swesGMX.balanceOf(account));
    }

    function claimableGMX(address account) public view returns(uint) {
        return vGMXTracker.withdrawable(account, vwesGMX.balanceOf(msg.sender));
    }

    function claimableETH(address account) public view returns(uint) {
        return sETHTracker.withdrawable(account, wsGMX.balanceOf(account) + swesGMX.balanceOf(account));
    }

    function claimEsGMX() external {
        uint amount = claimableEsGMX(msg.sender);
        sGMXTracker.withdraw(msg.sender, wsGMX.balanceOf(msg.sender) + swesGMX.balanceOf(msg.sender));
        _swesGMXmint(msg.sender, amount);
    }

    function claimETH() external {
        uint amount = claimableETH(msg.sender);
        sETHTracker.withdraw(msg.sender, wsGMX.balanceOf(msg.sender) + swesGMX.balanceOf(msg.sender));
        weth.withdrawTo(msg.sender, amount);
    }

    function claimGMX() external {
        uint amount = claimableGMX(msg.sender);
        vGMXTracker.withdraw(msg.sender, vwesGMX.balanceOf(msg.sender));
        _mint(msg.sender, amount);
    }

    function _distributeEsGMX(uint amount) internal {
        sGMXTracker.distribute(amount, wsGMX.totalSupply() + swesGMX.totalSupply());
    }

    function _distributeETH(uint amount) internal {
        sETHTracker.distribute(amount, wsGMX.totalSupply() + swesGMX.totalSupply());
    }

    function _distributeGMX(uint amount) internal {
        vGMXTracker.distribute(amount, vwesGMX.totalSupply());
    }

    function _deposit(address account, uint _amount) internal {
        wesGMX.burn(account, _amount);
        vester.deposit(_amount);
        _vwesGMXmint(account, _amount);
    }

    function _withdraw(address account, uint _amount) internal {
        _vwesGMXburn(account, _amount);
        uint esGmxBalance = esGMX.balanceOf(address(this));
        vester.withdraw();
        uint esGmxReceived = esGMX.balanceOf(address(this)) - esGmxBalance;
        uint esGmxKeeped = esGmxReceived - _amount;
        vester.deposit(esGmxKeeped);
        wesGMX.mint(account, _amount);
    }

    function _stakeGmx(address account, uint _amount) internal {
        _burn(account, _amount);
        underlying.approve(address(sGMX), _amount);
        rewardRouterV2.stakeGmx(_amount);
        _wsGMXmint(account, _amount);
    }

    function _stakeEsGmx(address account, uint _amount) internal {
        wesGMX.burn(account, _amount);
        rewardRouterV2.stakeEsGmx(_amount);
        _swesGMXmint(account, _amount);
    }

    function _unstakeGmx(address account, uint _amount) internal {
        _wsGMXburn(account, _amount);
        rewardRouterV2.unstakeGmx(_amount);
        _mint(account, _amount);
    }

    function _unstakeEsGmx(address account, uint _amount) internal {
        _swesGMXburn(account, _amount);
        rewardRouterV2.unstakeEsGmx(_amount);
        wesGMX.mint(account, _amount);
    }

    function _swesGMXmint(address account, uint amount) internal {
        swesGMX.mint(account, amount);
        sGMXTracker.mint(account, amount);
        sETHTracker.mint(account, amount);
    }

    function _swesGMXburn(address account, uint amount) internal {
        swesGMX.burn(account, amount);
        sGMXTracker.burn(account, amount);
        sETHTracker.burn(account, amount);
    }

    function _wsGMXmint(address account, uint amount) internal {
        wsGMX.mint(account, amount);
        sGMXTracker.mint(account, amount);
        sETHTracker.mint(account, amount);
    }

    function _wsGMXburn(address account, uint amount) internal {
        wsGMX.burn(account, amount);
        sGMXTracker.burn(account, amount);
        sETHTracker.burn(account, amount);
    }


    function _vwesGMXburn(address account, uint amount) internal {
        vwesGMX.burn(account, amount);
        vGMXTracker.burn(account, amount);
    }

    function _vwesGMXmint(address account, uint amount) internal {
        vwesGMX.mint(account, amount);
        vGMXTracker.mint(account, amount);
    }

    function onTransfer(address from ,address to, uint amount) external {
        address token = msg.sender;

        if(token == address(wsGMX) || token == address(swesGMX)) {
            sGMXTracker.transfer(from, to, amount);
            sETHTracker.transfer(from, to, amount);
        }
        if(token == address(vwesGMX)) {
            vGMXTracker.transfer(from, to, amount);
        }
    }

    function destroy() external onlyOwner {
        selfdestruct(payable(owner()));
    }
}

