// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UniswapV2Library.sol";
import "./UniswapV3Library.sol";
import "./IPLPS.sol";
import "./ArbitrumBlockProvider.sol";

abstract contract UsingLiquidityProtectionService {
    bool private unProtected = false;
    bool private unProtectedExtra = false;
    IPLPS private plps;
    uint64 internal constant HUNDRED_PERCENT = 1e18;
    bytes32 internal constant UNISWAP = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    bytes32 internal constant UNISWAP_V3 = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
    bytes32 internal constant PANCAKESWAP = 0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;
    bytes32 internal constant PANCAKESWAP_V3 = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;
    bytes32 internal constant QUICKSWAP = UNISWAP;
    bytes32 internal constant SUSHISWAP = 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 internal constant PANGOLIN = 0x40231f6b438bce0797c9ada29b718a87ea0a5cea3fe9a771abdd76bd41a3e545;
    bytes32 internal constant TRADERJOE = 0x0bbca9af0511ad1a1da383135cf3a8d2ac620e549ef9f6ae3a4c33c2fed0af91;
    bytes32 internal constant CAMELOT = 0xa856464ae65f7619087bc369daaf7e387dae1e5af69cfa7935850ebf754b04c1;
    bytes32 internal constant UNISWAP_ARBITRUM_V3 = UNISWAP_V3;

    enum UniswapVersion {
        V2,
        V3
    }

    enum UniswapV3Fees {
        _001, // 0.01%
        _005, // 0.05%
        _025, // 0.25%
        _03, // 0.3%
        _1 // 1%
    }

    modifier onlyProtectionAdmin() {
        protectionAdminCheck();
        _;
    }

    constructor (address _plps) {
        plps = IPLPS(_plps);
    }

    function LiquidityProtection_setLiquidityProtectionService(IPLPS _plps) external onlyProtectionAdmin() {
        require(token_balanceOf(getLiquidityPool()) == 0, 'UsingLiquidityProtectionService: liquidity already added');
        plps = _plps;
    }

    function chain_blockNumber() internal virtual view returns(uint);
    function token_transfer(address from, address to, uint amount) internal virtual;
    function token_balanceOf(address holder) internal view virtual returns(uint);
    function protectionAdminCheck() internal view virtual;
    function uniswapVariety() internal pure virtual returns(bytes32);
    function uniswapVersion() internal pure virtual returns(UniswapVersion);
    // For PancakeV3 factory is the PoolDelpoyer address.
    function uniswapFactory() internal pure virtual returns(address);
    function counterToken() internal pure virtual returns(address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    }
    function uniswapV3Fee() internal pure virtual returns(UniswapV3Fees) {
        return UniswapV3Fees._03;
    }
    function protectionChecker() internal view virtual returns(bool) {
        return ProtectionSwitch_manual();
    }
    function protectionCheckerExtra() internal view virtual returns(bool) {
        return ProtectionSwitch_manual_extra();
    }

    function lps() private view returns(IPLPS) {
        return plps;
    }

    function LiquidityProtection_beforeTokenTransfer(address _from, address _to, uint _amount) internal virtual {
        if (protectionChecker()) {
            if (not(unProtected)) {
                lps().LiquidityProtection_beforeTokenTransfer(getLiquidityPool(), _from, _to, _amount);
            }
            if (not(unProtectedExtra)) {
                lps().LiquidityProtection_beforeTokenTransfer_extra(getLiquidityPool(), _from, _to, _amount);
            }
        } else if (protectionCheckerExtra() && not(unProtectedExtra)) {
            lps().LiquidityProtection_beforeTokenTransfer_extra(getLiquidityPool(), _from, _to, _amount);
        }
    }

    function revokeBlocked(address[] calldata _holders, address _revokeTo) external onlyProtectionAdmin() {
        require(protectionChecker(), 'UsingLiquidityProtectionService: protection removed');
        bool unProtectedOld = unProtected;
        bool unProtectedExtraOld = unProtectedExtra;
        unProtected = true;
        unProtectedExtra = true;
        address pool = getLiquidityPool();
        for (uint i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            if (lps().isBlocked(pool, holder)) {
                token_transfer(holder, _revokeTo, token_balanceOf(holder));
            }
        }
        unProtected = unProtectedOld;
        unProtectedExtra = unProtectedExtraOld;
    }

    function LiquidityProtection_unblock(address[] calldata _holders) external onlyProtectionAdmin() {
        require(protectionChecker(), 'UsingLiquidityProtectionService: protection removed');
        address pool = getLiquidityPool();
        lps().unblock(pool, _holders);
    }

    function LiquidityProtection_manualBlock(address[] calldata _holders) external onlyProtectionAdmin() {
        require(protectionChecker(), 'UsingLiquidityProtectionService: protection removed');
        address pool = getLiquidityPool();
        lps().manualBlock(pool, _holders);
    }

    function LiquidityProtection_setWhitelist(address[] calldata _holders, bool _value) external onlyProtectionAdmin() {
        lps().setWhitelist(_holders, _value);
    }

    function disableProtection() external onlyProtectionAdmin() {
        unProtected = true;
    }

    function disableProtectionExtra() external onlyProtectionAdmin() {
        unProtectedExtra = true;
    }

    function isProtected() public view returns(bool) {
        return not(unProtected);
    }

    function isProtectedExtra() public view returns(bool) {
        return not(unProtectedExtra);
    }

    function ProtectionSwitch_manual() internal view returns(bool) {
        return isProtected();
    }

    function ProtectionSwitch_manual_extra() internal view returns(bool) {
        return isProtectedExtra();
    }

    function ProtectionSwitch_timestamp(uint _timestamp) internal view returns(bool) {
        return not(passed(_timestamp));
    }

    function ProtectionSwitch_block(uint _block) internal view returns(bool) {
        return not(blockPassed(_block));
    }

    function blockNumber_Native() internal view returns(uint) {
        return block.number;
    }

    function blockNumber_Arbitrum() internal view returns(uint) {
        return ArbitrumBlockProvider.blockNumber();
    }

    function blockPassed(uint _block) internal virtual view returns(bool) {
        return _block < chain_blockNumber();
    }

    function passed(uint _timestamp) internal view returns(bool) {
        return _timestamp < block.timestamp;
    }

    function not(bool _condition) internal pure returns(bool) {
        return !_condition;
    }

    function feeToUint24(UniswapV3Fees _fee) internal pure returns(uint24) {
        if (_fee == UniswapV3Fees._03) return 3000;
        if (_fee == UniswapV3Fees._025) return 2500;
        if (_fee == UniswapV3Fees._005) return 500;
        if (_fee == UniswapV3Fees._001) return 100;
        return 10000;
    }

    function getLiquidityPool() public view returns(address) {
        if (uniswapVersion() == UniswapVersion.V2) {
            return UniswapV2Library.pairFor(uniswapVariety(), uniswapFactory(), address(this), counterToken());
        }
        require(uniswapVariety() == UNISWAP_V3 || uniswapVariety() == PANCAKESWAP_V3, 'LiquidityProtection: uniswapVariety() can only be UNISWAP for V3.');
        return UniswapV3Library.computeAddress(uniswapVariety(), uniswapFactory(),
            UniswapV3Library.getPoolKey(address(this), counterToken(), feeToUint24(uniswapV3Fee())));
    }
}

