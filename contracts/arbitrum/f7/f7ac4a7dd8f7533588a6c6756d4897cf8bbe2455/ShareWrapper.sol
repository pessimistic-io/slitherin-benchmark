// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Abs.sol";
import "./IChainLink.sol";
import "./IWETH.sol";
import "./IGlpVault.sol";

contract ShareWrapper {

    using SafeERC20 for IERC20;
    using Abs for int256;

    address public share = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address public shareOracel = address(0xB1552C5e96B312d0Bf8b554186F846C40614a540);

    address public weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    uint256 public fee;
    address public feeTo;

    struct TotalSupply {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
    }

    struct Balances {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
    }

    mapping(address => Balances) internal _balances;
    TotalSupply internal _totalSupply;

    function total_supply_wait() public view returns (uint256) {
        return _totalSupply.wait;
    }

    function total_supply_staked() public view returns (uint256) {
        return _totalSupply.staked;
    }

    function total_supply_withdraw() public view returns (uint256) {
        return _totalSupply.withdrawable;
    }

    function total_supply_reward() public view returns (int256) {
        return _totalSupply.reward;
    }

    function balance_wait(address account) public view returns (uint256) {
        return _balances[account].wait;
    }

    function balance_staked(address account) public view returns (uint256) {
        return _balances[account].staked;
    }

    function balance_withdraw(address account) public view returns (uint256) {
        return _balances[account].withdrawable;
    }

    function balance_reward(address account) public view returns (int256) {
        return _balances[account].reward;
    }

    function share_price() public view returns (uint256) {
        (,int256 answer,,,)= IChainLink(shareOracel).latestRoundData();
        return answer.abs();
    }

    function share_price_decimals() public view returns (uint256) {
        return IChainLink(shareOracel).decimals();
    }

    function get_same_value_wsteth_from_weth(uint256 amount) public view returns (uint256) {
        return amount * 10 ** share_price_decimals() / share_price();
    }

    function stake(uint256 amount) public payable virtual {
        _totalSupply.wait += amount;
        _balances[msg.sender].wait += amount;
        IERC20(share).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount, bool convert_weth) public virtual {
        require(_balances[msg.sender].withdrawable >= amount, "withdraw amount greater than withdrawable");
        _totalSupply.withdrawable -= amount;
        _balances[msg.sender].withdrawable -= amount;
        int _reward = balance_reward(msg.sender);
        if (_reward > 0) {
            _balances[msg.sender].reward = 0;
            _totalSupply.reward -= _reward;
            IERC20(share).safeTransfer(msg.sender, amount);
            if (!convert_weth){
                IERC20(weth).safeTransfer(msg.sender, _reward.abs());
            }else{
                if (address(this).balance < _reward.abs()){
                    IWETH(weth).withdraw(_reward.abs());
                }
                Address.sendValue(payable(msg.sender), _reward.abs());
            }
        } else if (_reward < 0) {
            require(amount > get_same_value_wsteth_from_weth(_reward.abs()), "withdraw value + reward value < 0");
            _balances[msg.sender].reward = 0;
            _totalSupply.reward -= _reward;
            IERC20(share).safeTransfer(msg.sender, amount - get_same_value_wsteth_from_weth(_reward.abs()));            
        } else {
            IERC20(share).safeTransfer(msg.sender, amount);
        }
    }
}
