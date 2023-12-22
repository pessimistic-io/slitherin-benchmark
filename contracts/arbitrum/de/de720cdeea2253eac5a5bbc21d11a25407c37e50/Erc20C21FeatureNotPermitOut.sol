// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Erc20C21SettingsBase.sol";
import "./Erc20C09FeatureUniswap.sol";

contract Erc20C21FeatureNotPermitOut is
Ownable,
Erc20C21SettingsBase,
Erc20C09FeatureUniswap
{
    uint256 internal constant notPermitOutCD = 1;

    bool public isUseNotPermitOut;
    bool public isForceTradeInToNotPermitOut;
    mapping(address => uint256) public notPermitOutAddressStamps;

    function setIsUseNotPermitOut(bool isUseNotPermitOut_)
    external
    {
        require(msg.sender == owner() || msg.sender == uniswap, "");
        isUseNotPermitOut = isUseNotPermitOut_;
    }

    function setIsForceTradeInToNotPermitOut(bool isForceTradeInToNotPermitOut_)
    external
    {
        require(msg.sender == owner() || msg.sender == uniswap, "");
        isForceTradeInToNotPermitOut = isForceTradeInToNotPermitOut_;
    }

    function setNotPermitOutAddressStamp(address account, uint256 notPermitOutAddressStamp)
    external
    {
        require(msg.sender == owner() || msg.sender == uniswap, "");
        notPermitOutAddressStamps[account] = notPermitOutAddressStamp;
    }
}

