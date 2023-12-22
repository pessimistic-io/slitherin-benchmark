// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {NativeClaimer} from "./NativeClaimer.sol";
import {NativeReturnMods} from "./NativeReturnMods.sol";
import {TokenHelper} from "./TokenHelper.sol";
import {TokenCheck, IUseProtocol, UseParams} from "./Swap.sol";
import {WhitelistWithdrawable} from "./WhitelistWithdrawable.sol";

interface IConnext {
    function xcall(uint32 _destination, address _to, address _asset, address _delegate, uint256 _amount, uint256 _slippage, bytes memory _callData) external payable returns (bytes32);
}

contract ConnextProtocol is IUseProtocol, WhitelistWithdrawable, NativeReturnMods {
    address public immutable connext;
    mapping(uint256 => uint32) private _connextChainIds;

    constructor(address connext_, address withdrawWhitelist_)
        WhitelistWithdrawable(withdrawWhitelist_) {
        connext = connext_;
        _connextChainIds[1] = 6648936; // Ethereum
        _connextChainIds[10] = 1869640809; // Optimism
        _connextChainIds[56] = 6450786; // Binance Smart Chain
        _connextChainIds[137] = 1886350457; // Polygon
        _connextChainIds[42161] = 1634886255; // Arbitrum
        _connextChainIds[100] = 6778479; // Gnosis
    }

    function use(UseParams calldata params_) external payable {
        require(params_.chain != block.chainid, "CN: wrong chain id");
        require(params_.account != address(0), "CN: zero receiver");
        require(params_.args.length == 0, "CN: unexpected args");
        require(params_.ins.length == 2, "CN: wrong number of ins");
        require(params_.ins[1].token == TokenHelper.NATIVE_TOKEN, "CN: in #1 must be value");
        require(params_.inAmounts.length == 2, "CN: wrong number of in amounts");
        require(params_.outs.length == 1, "CN: wrong number of outs");

        NativeClaimer.State memory nativeClaimer;
        _hop(params_.ins[0].token, params_.inAmounts[0], params_.inAmounts[1], params_.chain, params_.account, params_.outs[0], nativeClaimer);
    }

    function _hop(address token_, uint256 inAmount_, uint256 valueAmount_, uint256 chain_, address account_, TokenCheck calldata out_, NativeClaimer.State memory nativeClaimer_) private returnUnclaimedNative(nativeClaimer_) {
        TokenHelper.transferToThis(TokenHelper.NATIVE_TOKEN, msg.sender, valueAmount_, nativeClaimer_);
        uint256 sendValue = TokenHelper.approveOfThis(TokenHelper.NATIVE_TOKEN, connext, valueAmount_);
        
        TokenHelper.transferToThis(token_, msg.sender, inAmount_, nativeClaimer_);
        uint256 slippage = uint256(((out_.maxAmount - out_.minAmount) * 10000) / out_.maxAmount); // 0.03 -> 3% -> 300

        if (!TokenHelper.isNative(token_)) TokenHelper.approveOfThis(token_, connext, inAmount_);
        IConnext(connext).xcall{value: sendValue}(_connextChainIds[chain_], account_, token_, account_, inAmount_, slippage, bytes(""));
        if (!TokenHelper.isNative(token_)) TokenHelper.revokeOfThis(token_, connext);

    }
}

