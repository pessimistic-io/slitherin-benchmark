// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Ownable} from "./Ownable.sol";
import {Multicall} from "./Multicall.sol";

import {WhitelistWithdrawable} from "./WhitelistWithdrawable.sol";
import {NativeReturnMods, NativeClaimer, TokenHelper} from "./NativeReturnMods.sol";
import {TokenCheck, IUseProtocol, UseParams} from "./Swap.sol";

struct LzTxObj {
    uint256 dstGasForCall;
    uint256 dstNativeAmount;
    bytes dstNativeAddr;
}

interface IStargate {
    function swap(uint16 dstChainId, uint256 srcPoolId, uint256 dstPoolId, address refundAddress, uint256 amountLD, uint256 minAmountLD, LzTxObj memory lzTxParams, bytes calldata to, bytes calldata payload) external payable;
}

contract StargateProtocol is IUseProtocol, Ownable, Multicall, WhitelistWithdrawable, NativeReturnMods {
    event ChainIdSet(uint256 chain, uint16 chainId);
    event ChainIdUnset(uint256 chain);
    event PoolIdSet(uint256 chain, address token, uint256 poolId);
    event PoolIdUnset(uint256 chain, address token);
    event DecimalsSet(uint256 chain, address token, uint8 decimals);
    event DecimalsUnset(uint256 chain, address token);

    address public immutable stargate;
    mapping(uint256 => uint16) public chainIds;
    mapping(uint256 => mapping(address => uint256)) public poolIds;
    mapping(uint256 => mapping(address => uint16)) public _decimals;

    constructor(address stargate_, address withdrawWhitelist_)
        WhitelistWithdrawable(withdrawWhitelist_) {
        stargate = stargate_;
    }

    function use(UseParams calldata params_) external payable {
        require(params_.chain != block.chainid, "SG: wrong chain id");
        require(params_.account != address(0), "SG: zero receiver");
        require(params_.args.length == 0, "SG: unexpected args");
        require(params_.ins.length == 2, "SG: wrong number of ins");
        require(params_.ins[1].token == TokenHelper.NATIVE_TOKEN, "SG: in #1 must be value");
        require(params_.inAmounts.length == 2, "SG: wrong number of in amounts");
        require(params_.outs.length == 1, "SG: wrong number of outs");

        NativeClaimer.State memory nativeClaimer;
        uint8 currentDecimals = requiredDecimals(params_.chain, params_.outs[0].token);
        uint8 targetDecimals = requiredDecimals(block.chainid, params_.ins[0].token);
        uint256 minAmountLD = params_.outs[0].minAmount;
        if (currentDecimals < targetDecimals) minAmountLD *= (10 ** (targetDecimals - currentDecimals));
        else if (currentDecimals > targetDecimals) minAmountLD /= (10 ** (currentDecimals - targetDecimals));

        _hop(params_.ins[0].token, params_.inAmounts[0], params_.inAmounts[1], params_.outs[0], params_.chain, params_.account, minAmountLD, nativeClaimer);
    }

    function setChainId(uint256 chain_, uint16 chainId_) external onlyOwner {
        require(chainId_ != 0, "SG: zero chain id");
        _setChainId(chain_, chainId_);
        emit ChainIdSet(chain_, chainId_);
    }

    function unsetChainId(uint256 chain_) external onlyOwner {
        _setChainId(chain_, 0);
        emit ChainIdUnset(chain_);
    }

    function _setChainId(uint256 chain_, uint16 chainId_) private {
        require(chainIds[chain_] != chainId_, "SG: same chain id");
        chainIds[chain_] = chainId_;
    }

    function setPoolId(uint256 chain_, address token_, uint256 poolId_) external onlyOwner {
        require(poolId_ != 0, "SG: zero pool id");
        _setPoolId(chain_, token_, poolId_);
        emit PoolIdSet(chain_, token_, poolId_);
    }

    function unsetPoolId(uint256 chain_, address token_) external onlyOwner {
        _setPoolId(chain_, token_, 0);
        emit PoolIdUnset(chain_, token_);
    }

    function _setPoolId(uint256 chain_, address token_, uint256 poolId_) private {
        require(poolIds[chain_][token_] != poolId_, "SG: same pool id");
        poolIds[chain_][token_] = poolId_;
    }

    function setDecimals(uint256 chainId_, address token_, uint8 decimals_) external onlyOwner {
        _setDecimalsValue(chainId_, token_, (uint16(1) << 15) | decimals_);
        emit DecimalsSet(chainId_, token_, decimals_);
    }
    
    function unsetDecimals(uint256 chainId_, address token_) external onlyOwner {
        _setDecimalsValue(chainId_, token_, 0);
        emit DecimalsUnset(chainId_, token_);
    }

    function hasDecimals(uint256 chainId_, address token_) public view returns (bool) {
        return _decimals[chainId_][token_] != 0;
    }

    function requiredDecimals(uint256 chainId_, address token_) private view returns (uint8) {
        require(hasDecimals(chainId_, token_), "SG: no decimals");
        return decimals(chainId_, token_);
    }

    function decimals(uint256 chainId_, address token_) public view returns (uint8) {
        return uint8(_decimals[chainId_][token_]);
    }

    function _setDecimalsValue(uint256 chainId_, address token_, uint16 decimals_) private {
        require(_decimals[chainId_][token_] != decimals_, "SG: same decimals");
        _decimals[chainId_][token_] = decimals_;
    }

    function _hop(address inToken_, uint256 inAmount_, uint256 valueAmount_, TokenCheck calldata out_, uint256 chain_, address account_, uint256 minAmountLD_, NativeClaimer.State memory nativeClaimer_) private returnUnclaimedNative(nativeClaimer_) {

        TokenHelper.transferToThis(TokenHelper.NATIVE_TOKEN, msg.sender, valueAmount_, nativeClaimer_);
        uint256 sendValue = TokenHelper.approveOfThis(TokenHelper.NATIVE_TOKEN, stargate, valueAmount_);

        TokenHelper.transferToThis(inToken_, msg.sender, inAmount_, nativeClaimer_);
        if (!TokenHelper.isNative(inToken_)) TokenHelper.approveOfThis(inToken_, stargate, inAmount_);

        IStargate(stargate).swap{value: sendValue}(chainIds[chain_], poolIds[block.chainid][inToken_], poolIds[chain_][out_.token], msg.sender, inAmount_, minAmountLD_, LzTxObj(0, 0, "0x"), abi.encodePacked(account_), bytes(""));

        if (!TokenHelper.isNative(inToken_)) TokenHelper.revokeOfThis(inToken_, stargate);
    }
}

