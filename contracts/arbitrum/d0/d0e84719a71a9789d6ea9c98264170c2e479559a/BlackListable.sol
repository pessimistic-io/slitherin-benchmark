// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";

abstract contract BlackListable is ERC20{
    //黑名单映射
    mapping(address => bool) isBlackListed;
    //事件
    event DestroyedBlackFunds(address _blackListedUser, uint _balance);
    event AddedBlackList(address _user);
    event RemovedBlackList(address _user);


    //Getters to allow the same blacklist to be used also by other contracts (including upgraded Tether)
    //允许其他合约调用此黑名单(external)，查看此人是否被列入黑名单
    function getBlackListStatus(address _maker) external view returns(bool){
        return isBlackListed[_maker];
    }

    //增加黑名单
    function addBlackList(address _evilUser) public onlyOwner{
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    //去除某人黑名单
    function removeBlackList(address _clearUser) public onlyOwner{
        isBlackListed[_clearUser] = false;
        emit RemovedBlackList(_clearUser);
    }
}


