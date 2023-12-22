// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ISurgeStaking} from "./ISurgeStaking.sol";
import {IRewarder} from "./IRewarder.sol";
import {IHLP} from "./IHlp.sol";

struct Balance {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 balance;
    uint256 totalSupply;
    string aka;
}

contract HlpAggregator is Initializable, OwnableUpgradeable {
    address public HLP_STAKING_PROXY;
    address public HLP_TOKEN_PROXY;
    ISurgeStaking private surgeStaking;
    IHLP private hlp;
    
    function initialize() public initializer {
        __Ownable_init();
        HLP_STAKING_PROXY = 0xbE8f8AF5953869222eA8D39F1Be9d03766010B1C;
        HLP_TOKEN_PROXY = 0x4307fbDCD9Ec7AEA5a1c2958deCaa6f316952bAb;
        surgeStaking = ISurgeStaking(HLP_STAKING_PROXY);
        hlp = IHLP(HLP_TOKEN_PROXY);
    }

    function changeHlpStakingProxy(address newAddress) public onlyOwner {
        HLP_STAKING_PROXY = newAddress;
        surgeStaking = ISurgeStaking(HLP_STAKING_PROXY);
    }

    function changeHlpTokenProxy(address newAddress) public onlyOwner {
        HLP_TOKEN_PROXY = newAddress;
        hlp = IHLP(HLP_TOKEN_PROXY);
    }

    function getBalances(address user) public returns(Balance[] memory balances) {
        balances = new Balance[](2 + surgeStaking.getRewarders().length);
        balances[0] = Balance(address(0), "","", hlp.decimals(), hlp.balanceOf(user), hlp.totalSupply(), "wallet");
        balances[1] = Balance(address(0), "","", hlp.decimals(), surgeStaking.userTokenAmount(user), hlp.totalSupply(), "staking");
        uint256 length = surgeStaking.getRewarders().length;
        for (uint256 i=0;i<length;i++) {
            IRewarder rewarder = IRewarder(surgeStaking.rewarders(i));
            IERC20Metadata token = IERC20Metadata(rewarder.rewardToken());
            balances[i+2] = Balance(rewarder.rewardToken(), token.name(), token.symbol(), token.decimals(), rewarder.pendingReward(user), token.totalSupply(), rewarder.name());
        }
        return balances;
    }
}
