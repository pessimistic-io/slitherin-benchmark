// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.19;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./Proxied.sol";

import "./IToUSDVLp.sol";

// from approvedToken to usdv, fees applicable
// owner can add and remove token.
// owenr can add a cap to the token
contract SidechainLP is IToUSDVLp, Proxied, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public lp;
    address public usdv;

    struct TokenConfig {
        bool enabled;
        uint16 feeBps;
        uint16 rewardBps; // give reward to whitelist users
        address receiver; // send the token to this address if balance exceeds cap
        uint cap; // balance cap
        uint div; // assuming other tokens have >= 6 decimal points
    }
    mapping(address token => TokenConfig) public tokenConfigs;
    EnumerableSet.AddressSet private addedTokens;
    mapping(address caller => bool) public whitelisted;
    uint private constant MAX_REWARD_BPS = 100;
    uint private constant MAX_FEE_BPS = 100;

    address public operator;

    event SwapToUSDV(address indexed caller, address indexed fromToken, uint fromTokenAmount, uint usdvOut);
    event DepositUSDV(uint amount, address source);
    event SetLp(address indexed lp);
    event WithdrawToken(address indexed token, uint amount, address target);
    event AddToken(address indexed token, uint cap, uint16 feeBps, uint16 rewardBps, address receiver);
    event RemoveToken(address token);
    event ConfigToken(address indexed token, uint cap, uint16 feeBps, uint16 rewardBps, bool enabled);
    event SetWhitelist(address indexed user, bool flag);
    event SetOperator(address operator);

    function initialize(address _usdv, address _operator, address _lp) public proxied initializer {
        __Ownable_init();
        __Pausable_init();
        operator = _operator;
        usdv = _usdv;
        lp = _lp;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "SidechainLP: not operator");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "SidechainLP: not whitelisted");
        _;
    }

    // ======================== OWNER interfaces ========================

    // set lp
    function setLp(address _lp) external onlyOwner {
        lp = _lp;
        emit SetLp(_lp);
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
        emit SetOperator(_operator);
    }

    // only to lp
    // can withdraw any token
    function withdrawToken(address _token, uint _amount) external onlyOwner {
        IERC20(_token).safeTransfer(lp, _amount);
        emit WithdrawToken(_token, _amount, lp);
    }

    // only from lp. require approval first
    function depositUSDV(uint _amount) external onlyOperator {
        IERC20(usdv).safeTransferFrom(lp, address(this), _amount);
        emit DepositUSDV(_amount, lp);
    }

    function setPaused(bool _p) external onlyOperator {
        _p ? _pause() : _unpause();
    }

    // add token
    function addToken(
        address _token,
        uint _cap,
        uint16 _feeBps,
        uint16 _rewardBps,
        address _receiver
    ) external onlyOwner {
        require(_rewardBps <= MAX_REWARD_BPS, "SidechainLP: REWARDBPS_TOO_LARGE");
        require(_feeBps <= MAX_FEE_BPS, "SidechainLP: FEEBPS_TOO_LARGE");

        require(_token != address(0) && _token != usdv, "SidechainLP: invalid token");
        // don't check if token is added here and allow owner to update the config

        // set conversion rate
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        require(tokenDecimals >= 6, "SidechainLP: token decimals must >= 6"); // usdv tokenDecimals

        tokenConfigs[_token].enabled = true;
        tokenConfigs[_token].div = 10 ** (tokenDecimals - 6);
        tokenConfigs[_token].cap = _cap;
        tokenConfigs[_token].feeBps = _feeBps;
        tokenConfigs[_token].rewardBps = _rewardBps;
        tokenConfigs[_token].receiver = _receiver;

        addedTokens.add(_token);
        emit AddToken(_token, _cap, _feeBps, _rewardBps, _receiver);
    }

    function removeToken(address _token) external onlyOwner {
        require(addedTokens.contains(_token), "SidechainLP: TOKEN_NOT_EXISTS");
        addedTokens.remove(_token);
        delete tokenConfigs[_token];
        emit RemoveToken(_token);
    }

    // owner interface to configure token
    function configToken(
        address _token,
        uint _cap,
        uint16 _feeBps,
        uint16 _rewardBps,
        bool _enabled
    ) external onlyOperator {
        require(tokenConfigs[_token].div != 0, "SidechainLP: token not added");
        require(_feeBps <= MAX_FEE_BPS, "SidechainLP: feeBps too large");
        require(_rewardBps <= MAX_REWARD_BPS, "SidechainLP: rewardBps too large");
        tokenConfigs[_token].cap = _cap;
        tokenConfigs[_token].feeBps = _feeBps;
        tokenConfigs[_token].rewardBps = _rewardBps;
        tokenConfigs[_token].enabled = _enabled;
        emit ConfigToken(_token, _cap, _feeBps, _rewardBps, _enabled);
    }

    function setWhitelist(address _user, bool _flag) external onlyOperator {
        whitelisted[_user] = _flag;
        emit SetWhitelist(_user, _flag);
    }

    // ======================== SWAP interfaces ========================
    function swapToUSDV(
        address _fromToken,
        uint256 _fromTokenAmount,
        uint64 _minUSDVOut,
        address _receiver
    ) external override whenNotPaused onlyWhitelisted returns (uint usdvOut) {
        usdvOut = getUSDVOut(_fromToken, _fromTokenAmount);
        require(usdvOut >= _minUSDVOut, "SidechainLP: _minUSDVOut not reached");

        // transfer from user
        IERC20(_fromToken).safeTransferFrom(msg.sender, address(this), _fromTokenAmount);

        // transfer out the token if cap is reached
        TokenConfig memory cfg = tokenConfigs[_fromToken];
        uint bal = IERC20(_fromToken).balanceOf(address(this));
        if (cfg.cap < bal && cfg.receiver != address(0)) {
            IERC20(_fromToken).safeTransfer(cfg.receiver, bal);
        }

        // transfer usdv to user
        IERC20(usdv).safeTransfer(_receiver, usdvOut);
        emit SwapToUSDV(msg.sender, _fromToken, _fromTokenAmount, usdvOut);
    }

    function getUSDVOut(
        address _fromToken,
        uint _fromTokenAmount
    ) public view override whenNotPaused returns (uint usdvOut) {
        TokenConfig memory config = tokenConfigs[_fromToken];
        require(config.enabled, "SidechainLP: token not enabled");
        uint afterFee = _fromTokenAmount - (_fromTokenAmount * config.feeBps) / 10000;
        // add positive slippage / reward to the caller
        afterFee = afterFee + (_fromTokenAmount * config.rewardBps) / 10000;
        usdvOut = afterFee / config.div;
        require(IERC20(usdv).balanceOf(address(this)) >= usdvOut, "SidechainLP: not enough usdv");
    }

    function getUSDVOutVerbose(
        address _fromToken,
        uint _fromTokenAmount
    ) external view whenNotPaused returns (uint requestedOut, uint rewardOut) {
        TokenConfig memory config = tokenConfigs[_fromToken];
        require(config.enabled, "SidechainLP: token not enabled");
        requestedOut = (_fromTokenAmount - ((_fromTokenAmount * config.feeBps) / 10000)) / config.div;
        rewardOut = ((_fromTokenAmount * config.rewardBps) / 10000) / config.div;
        require(IERC20(usdv).balanceOf(address(this)) >= requestedOut + rewardOut, "SidechainLP: not enough usdv");
    }

    function getSupportedTokens() external view returns (address[] memory tokens) {
        tokens = addedTokens.values();
        uint index = 0;
        for (uint i = 0; i < tokens.length; i++) {
            if (tokenConfigs[tokens[i]].enabled) {
                tokens[index++] = tokens[i];
            }
        }
        assembly {
            mstore(tokens, index)
        }
    }

    function getAllTokens() external view returns (address[] memory tokens) {
        tokens = addedTokens.values();
    }
}

