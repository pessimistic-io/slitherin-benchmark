//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./console.sol";

import {ERC20Wrapper} from "./ERC20Wrapper.sol";
import {ERC20, IERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {wToken} from "./wToken.sol";
import {wLockedToken} from "./wLockedToken.sol";

import {DividendDistributor} from "./DividendDistributor.sol";

import {RewardRouterV2} from "./RewardRouterV2.sol";

import {Ownable} from "./Ownable.sol";

import {IVester} from "./IVester.sol";

import {PaymentSplitter} from "./PaymentSplitter.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address) external view returns (uint);
}

interface FeeGmxTracker is IERC20 {
    function depositBalances(address acccount, address token) external returns(uint balance);
}

contract wGMX is ERC20, ERC20Wrapper, Ownable, PaymentSplitter {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeERC20 for IERC20;
    using DividendDistributor for DividendDistributor.Distributor;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Stake(address indexed account, uint amount);
    event UnStake(address indexed account, uint amount);

    event DepositVault(address indexed account, uint amount);
    event WithdrawVault(uint gmxAmount, uint esgmxAmount, uint sbfgmxAmount);
    event Claim(address indexed account, address indexed receiver, Reward reward, uint amount);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_BalanceTooLow(address token, uint balance, uint request);

    /// -----------------------------------------------------------------------
    /// Enums
    /// -----------------------------------------------------------------------

    enum Distributor{ REWARD_GMX, REWARD_ETH, VAULT_GMX, VAULT_ESGMX }
    enum Reward{ REWARD_GMX, REWARD_ETH, VAULT_GMX, VAULT_ESGMX, VAULT_SBFGMX }

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    RewardRouterV2 public rewardRouterV2;
    IVester public immutable vester;

    address public stakedGmxTracker;

    FeeGmxTracker public immutable sbfGMX;
    IERC20 public immutable esGMX;

    DividendDistributor.Distributor public rewardGmxTracker;
    DividendDistributor.Distributor public rewardEthTracker;
    DividendDistributor.Distributor public vaultGmxTracker;
    DividendDistributor.Distributor public vaultEsGmxTracker;

    wLockedToken public immutable lwsGMX;
    wToken public immutable wsGMX;
    wToken public immutable wesGMX;
    wToken public immutable vwesGMX;

    IWETH public immutable weth;

    uint public reserves = 0;

    /// -----------------------------------------------------------------------
    /// Initialization
    /// -----------------------------------------------------------------------

    constructor(address _rewardRouter, address _gmx, address[] memory _holders, uint[] memory _shares_) ERC20("Wrapped GMX","wGMX") ERC20Wrapper(IERC20(_gmx)) PaymentSplitter(_holders, _shares_) {
        rewardRouterV2 = RewardRouterV2(_rewardRouter);
        vester = IVester(rewardRouterV2.gmxVester());

        stakedGmxTracker = rewardRouterV2.stakedGmxTracker();

        sbfGMX = FeeGmxTracker(rewardRouterV2.feeGmxTracker());
        esGMX = IERC20(rewardRouterV2.esGmx());

        wsGMX = new wToken("Wrapped Staked GMX", "wsGMX");
        wesGMX = new wToken("Staked Wrapped Escrowed GMX", "wesGMX");
        vwesGMX = new wToken("Vested Wrapped Escrowed GMX", "vwesGMX");
        lwsGMX = new wLockedToken("Locked Wrapped Staked GMX", "lwsGMX");

        weth = IWETH(rewardRouterV2.weth());

        rewardGmxTracker.setTokenReward(address(wesGMX));
        rewardEthTracker.setTokenReward(rewardRouterV2.weth());
        vaultGmxTracker.setTokenReward(address(this));
        vaultEsGmxTracker.setTokenReward(address(wesGMX));
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function handleRewards() external {
        uint balance_esGMX = esGMX.balanceOf(address(this));
        uint balance_eth = weth.balanceOf(address(this));
        uint balance_GMX = underlying.balanceOf(address(this));
        rewardRouterV2.handleRewards(true, false, true, false, true, true, false);
        uint received_esGMX = esGMX.balanceOf(address(this)) - balance_esGMX;
        uint received_eth = weth.balanceOf(address(this)) - balance_eth;
        uint received_GMX = underlying.balanceOf(address(this)) - balance_GMX;
        _distribute(Distributor.REWARD_ETH, received_eth);
        if(received_GMX > 0) {
            underlying.approve(stakedGmxTracker, received_GMX);
            rewardRouterV2.stakeGmx(received_GMX);
            wsGMX.mint(address(this), received_GMX);
            emit Stake(address(this), received_GMX);
            _distribute(Distributor.VAULT_GMX, received_GMX);
        }
        if(received_esGMX > 0){
            _distribute(Distributor.REWARD_GMX, received_esGMX);
            rewardRouterV2.stakeEsGmx(received_esGMX);
            emit Stake(address(0), received_esGMX);
        }
    }

    function stake(uint amount) external {
        _stake(msg.sender, amount);
    }

    function unstake(uint amount) external {
        _unstake(msg.sender, amount);
    }

    function deposit(uint amount) external {
        _deposit(msg.sender, amount);
    }

    function withdraw() external {
        _withdraw();
    }

    function claim(bool claimVaultGmx, bool stakeVaultGmx, bool claimVaultEsgmx, bool claimVaultReserve, bool claimEsGmxReward, bool claimEth) external {
        if(claimVaultGmx) {
            uint amount = _claim(Reward.VAULT_GMX, msg.sender, msg.sender);
            if(stakeVaultGmx) {
                _stake(msg.sender, amount);
            }
        }

        if(claimVaultEsgmx) {
            _claim(Reward.VAULT_ESGMX, msg.sender, msg.sender);
        }

        if(claimVaultReserve) {
            _claim(Reward.VAULT_SBFGMX, msg.sender, msg.sender);
        }

        if(claimEsGmxReward) {
            _claim(Reward.REWARD_GMX, msg.sender, msg.sender);
        }

        if(claimEth) {
            _claim(Reward.REWARD_ETH, msg.sender, msg.sender);
        }
    }


    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    function withdrawable(address account) external view returns(uint vaultGmx, uint vaultEsGmx, uint vaultReserve, uint rewardEsGmx, uint rewardEth) {
        vaultGmx = vaultGmxTracker.withdrawable(account, vaultOf(account));
        vaultEsGmx = vaultEsGmxTracker.withdrawable(account, vaultOf(account));
        vaultReserve = lwsGMX.balanceOf(account);
        if(vaultReserve > reserves) {
            vaultReserve = reserves;
        }
        rewardEsGmx = rewardGmxTracker.withdrawable(account, stakeOf(account));
        rewardEth = rewardEthTracker.withdrawable(account, stakeOf(account));
    }


    function totalVault() public view returns(uint) {
        return vwesGMX.totalSupply();
    }

    function vaultOf(address account) public view returns(uint) {
        return vwesGMX.balanceOf(account);
    }

    function totalStaked() public view returns(uint) {
        return wsGMX.totalSupply() + wesGMX.totalSupply() + lwsGMX.totalSupply();
    }

    function stakeOf(address account) public view returns(uint) {
        return wsGMX.balanceOf(account) + wesGMX.balanceOf(account) + lwsGMX.balanceOf(account);
    }

    /// -----------------------------------------------------------------------
    /// Plugins actions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    function destroy() external onlyOwner {
        selfdestruct(payable(owner()));
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _stake(address account, uint amount) internal {
        if(amount > balanceOf(account)) revert Error_BalanceTooLow(address(this), balanceOf(account), amount);
        _burn(account, amount);
        underlying.approve(stakedGmxTracker, amount);
        rewardRouterV2.stakeGmx(amount);
        wsGMX.mint(account, amount);
        emit Stake(account, amount);
    }

    function _unstake(address account, uint amount) internal {
        if(amount > wsGMX.balanceOf(account)) revert Error_BalanceTooLow(address(wsGMX), wsGMX.balanceOf(account), amount);
        wsGMX.burn(account, amount);
        rewardRouterV2.unstakeGmx(amount);
        _mint(account, amount);
        emit UnStake(account, amount);
    }

    function _deposit(address account, uint amount) internal {
        if(amount > wesGMX.balanceOf(account)) revert Error_BalanceTooLow(address(wesGMX), wesGMX.balanceOf(account), amount);
        wesGMX.burn(account, amount);
        rewardRouterV2.unstakeEsGmx(amount);
        uint balance_sbfGMX = sbfGMX.balanceOf(address(this));
        vester.deposit(amount);
        uint reserved_sbfGMX = balance_sbfGMX - sbfGMX.balanceOf(address(this));
        wsGMX.burn(account, reserved_sbfGMX);
        lwsGMX.mint(account, reserved_sbfGMX);
        emit DepositVault(account, amount);
    }

    function _withdraw() internal {
        uint balance_sbfGMX = sbfGMX.balanceOf(address(this));
        uint balance_GMX = underlying.balanceOf(address(this));
        uint balance_ESGMX = esGMX.balanceOf(address(this));
        vester.withdraw();
        uint received_GMX = underlying.balanceOf(address(this)) - balance_GMX;
        uint received_ESGMX = esGMX.balanceOf(address(this)) - balance_ESGMX;
        uint received_sbfGMX = sbfGMX.balanceOf(address(this)) - balance_sbfGMX;
        esGMX.approve(stakedGmxTracker, received_ESGMX);
        rewardRouterV2.stakeEsGmx(received_ESGMX);
        _distribute(Distributor.VAULT_ESGMX, received_ESGMX);
        _distribute(Distributor.VAULT_GMX, received_GMX);

        underlying.approve(stakedGmxTracker, received_GMX);
        rewardRouterV2.stakeGmx(received_GMX);
        wsGMX.mint(address(this), received_GMX);
        emit Stake(address(this), received_GMX);

        reserves += received_sbfGMX;
        emit WithdrawVault(received_GMX, received_ESGMX, received_sbfGMX);
    }

    function _claim(Reward reward, address from, address to) internal returns(uint amount) {
        if(reward == Reward.REWARD_ETH) {
            amount = rewardEthTracker.withdrawable(from, stakeOf(from));
            rewardEthTracker.withdraw(from, stakeOf(from));
            weth.withdraw(amount);
            payable(to).transfer(amount);
        }

        if(reward == Reward.REWARD_GMX) {
            amount = rewardGmxTracker.withdrawable(from, stakeOf(from));
            rewardGmxTracker.withdraw(from, stakeOf(from));
            wesGMX.mint(to, amount);
        }

        if(reward == Reward.VAULT_ESGMX) {
            amount = vaultEsGmxTracker.withdrawable(from, vaultOf(from));
            vaultEsGmxTracker.withdraw(from, vaultOf(from));
            wesGMX.mint(to, amount);
        }

        if(reward == Reward.VAULT_GMX) {
            amount = vaultGmxTracker.withdrawable(from, vaultOf(from));
            vaultGmxTracker.withdraw(from, vaultOf(from));
            rewardRouterV2.unstakeGmx(amount);
            wsGMX.burn(address(this), amount);
            emit UnStake(address(this), amount);
            _mint(to, amount);
        }

        if(reward == Reward.VAULT_SBFGMX) {
            amount = lwsGMX.balanceOf(from);
            if(amount > reserves) {
                amount = reserves;
            }
            lwsGMX.burn(from, amount);
            wsGMX.mint(to, amount);
            reserves -= amount;
        }

        emit Claim(from, to, reward, amount);
    }

    function _distribute(Distributor distributor, uint amount) internal {
        if(distributor == Distributor.REWARD_GMX) {
            rewardGmxTracker.distribute(amount, totalStaked());
        }

        if(distributor == Distributor.REWARD_ETH) {
            rewardEthTracker.distribute(amount, totalStaked());
        }

        if(distributor == Distributor.VAULT_GMX) {
            vaultGmxTracker.distribute(amount, totalVault());
        }

        if(distributor == Distributor.VAULT_ESGMX) {
            vaultEsGmxTracker.distribute(amount, totalVault());
        }
    }

    /// -----------------------------------------------------------------------
    /// Token functions
    /// -----------------------------------------------------------------------

    function onTransfer(address from ,address to, uint amount) external {
        address token = msg.sender;

        if(token == address(wsGMX) || token == address(wesGMX) || token == address(lwsGMX)){
            if(from == address(0)) {
                rewardGmxTracker.mint(to, amount);
                rewardEthTracker.mint(to, amount);
            }

            if(to == address(0)) {
                rewardGmxTracker.burn(from, amount);
                rewardEthTracker.burn(from, amount);
            }

            if(from != to && from != address(0) && to != address(0)) {
                rewardGmxTracker.transfer(from, to, amount);
                rewardEthTracker.transfer(from, to, amount);
            }
        }

        if(token == address(vwesGMX)) {
            if(from == address(0)) {
                vaultGmxTracker.mint(to, amount);
                vaultEsGmxTracker.mint(to, amount);
            }

            if(to == address(0)) {
                vaultGmxTracker.burn(from, amount);
                vaultEsGmxTracker.burn(from, amount);
            }

            if(from != to && from != address(0) && to != address(0)) {
                uint balance = vwesGMX.balanceOf(from) + amount;
                uint lockedAmount = (lwsGMX.balanceOf(from) * amount) / balance;
                lwsGMX.manage(from, to, lockedAmount);
                vaultGmxTracker.transfer(from, to, amount);
                vaultEsGmxTracker.transfer(from, to, amount);
            }
        }
    }
}

