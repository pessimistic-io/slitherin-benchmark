// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IFeeConfig.sol";

contract CpCHRConfigurator is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    uint256 public constant MAX_RATE = 1e18;
    uint256 public constant MAX = 10000; // 100%

    address public coFeeRecipient;
    IFeeConfig public coFeeConfig;

    uint256 public reserveRate;

    uint256 public minDuringTimeWithdraw;
    uint256 public redeemFeePercent;
    bool public isAutoIncreaseLock;

    bool public isPausedDeposit;
    bool public isPausedDepositVe;

    uint256 public maxPeg;

    address[] public excluded;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;

    mapping (address => bool) public marketLpPairs;
    uint256 public taxSellingPercent;
    mapping(address => bool) public excludedSellingTaxAddresses;

    uint256 public taxBuyingPercent;
    mapping(address => bool) public excludedBuyingTaxAddresses;

    event SetRedeemFeePercent(uint256 oldValue, uint256 newValue);
    event SetMinDuringTimeWithdraw(uint256 oldValue, uint256 newValue);
    event SetMaxPeg(uint256 oldValue, uint256 newValue);
    event SetReserveRate(uint256 oldValue, uint256 newValue);
    event SetTaxSellingPercent(uint256 oldValue, uint256 newValue);
    event SetTaxBuyingPercent(uint256 oldValue, uint256 newValue);
    event SetFeeRecipient(address oldRecipient, address newRecipient);
    event SetFeeId(uint256 id);
    event AutoIncreaseLock(bool _enabled);

    event GrantExclusion(address indexed account);
    event RevokeExclusion(address indexed account);

    function initialize(address _coFeeConfig, address _coFeeRecipient) public initializer {
        __Ownable_init();
        coFeeRecipient = _coFeeRecipient;
        coFeeConfig = IFeeConfig(_coFeeConfig);

        redeemFeePercent = 200; // 2%
        isAutoIncreaseLock = true;
        maxPeg = 0.85e18;
        reserveRate = 2000; // 20%
        taxBuyingPercent = 100; // 1%
        taxSellingPercent = 100; // 1%

        excluded.push(deadWallet);
    }

    function setRedeemFeePercent(uint256 _rate) external onlyOwner {
        // validation from 0-2%
        require(_rate <= 200, "CpCHRConfigurator: RATE_OUT_OF_RANGE");
        emit SetRedeemFeePercent(redeemFeePercent, _rate);
        redeemFeePercent = _rate;
    }
    
    function setMinDuringTimeWithdraw(uint256 _seconds) external onlyOwner {
        // validation from 0-24h
        require(_seconds <= 24 hours, "CpCHRConfigurator: OUT_OF_RANGE");
        emit SetMinDuringTimeWithdraw(minDuringTimeWithdraw, _seconds);
        minDuringTimeWithdraw = _seconds;
    }

    function setAutoIncreaseLock(bool _enabled) external onlyOwner {
        isAutoIncreaseLock = _enabled;
        emit AutoIncreaseLock(_enabled);
    }

    function setMaxPeg(uint256 _value) external onlyOwner {
        // validation from 0-1
        require(_value <= 1e18, "CpCHRConfigurator: VALUE_OUT_OF_RANGE");
        emit SetMaxPeg(maxPeg, _value);
        maxPeg = _value;
    }

    function adjustReserve(uint256 _rate) external onlyOwner {
        // validation from 0-50%
        require(_rate <= 5000, "CpCHRConfigurator: OUT_OF_RANGE");
        emit SetReserveRate(reserveRate, _rate);
        reserveRate = _rate;
    }

    // Add new LP's for selling / buying fees
    function setMarketLpPairs(address _pair, bool _value) public onlyOwner {
        marketLpPairs[_pair] = _value;
    }

    function setTaxBuyingPercent(uint256 _value) external onlyOwner {
		require(_value <= 100, "Max tax is 1%");
        emit SetTaxBuyingPercent(taxBuyingPercent, _value);
        taxBuyingPercent = _value;
    }

    function setTaxSellingPercent(uint256 _value) external onlyOwner {
		require(_value <= 100, "Max tax is 1%");
        emit SetTaxSellingPercent(taxSellingPercent, _value);
        taxSellingPercent = _value;
    }

    function pauseDeposit(bool _paused) external onlyOwner {
        isPausedDeposit = _paused;
    }

    function pauseDepositVe(bool _paused) external onlyOwner {
        isPausedDepositVe = _paused;
    }

    function excludeBuyingTaxAddress(address _address) external onlyOwner {
        excludedBuyingTaxAddresses[_address] = true;
    }

    function excludeSellingTaxAddress(address _address) external onlyOwner {
        excludedSellingTaxAddresses[_address] = true;
    }

    function includeBuyingTaxAddress(address _address) external onlyOwner {
        excludedBuyingTaxAddresses[_address] = false;
    }

    function includeSellingTaxAddress(address _address) external onlyOwner {
        excludedSellingTaxAddresses[_address] = false;
    }

    function grantExclusion(address account) external onlyOwner {
        excluded.push(account);
        emit GrantExclusion(account);
    }

    function revokeExclusion(address account) external onlyOwner {
        uint256 excludedLength = excluded.length;
        for (uint256 i = 0; i < excludedLength; i++) {
            if (excluded[i] == account) {
                excluded[i] = excluded[excludedLength - 1];
                excluded.pop();
                emit RevokeExclusion(account);
                return;
            }
        }
    }

    function setFeeId(uint256 id) external onlyOwner {
        emit SetFeeId(id);
        coFeeConfig.setStratFeeId(id);
    }

    function setCoFeeRecipient(address _feeRecipient) external onlyOwner {
        emit SetFeeRecipient(address(coFeeRecipient), _feeRecipient);
        coFeeRecipient = _feeRecipient;
    }

    function hasSellingTax(address _from, address _to) external view returns (uint256) {
        if(marketLpPairs[_to] && !excludedSellingTaxAddresses[_from] && taxSellingPercent > 0) {
            return taxSellingPercent;
        }

        return 0;
    }

    function hasBuyingTax(address _from, address _to) external view returns (uint256) {
        if(marketLpPairs[_from] && !excludedBuyingTaxAddresses[_to] && taxBuyingPercent > 0) {
            return taxBuyingPercent;
        }

        return 0;
    }

    function getExcluded() external view returns (address[] memory) {
        return excluded;
    }

    function getFee() external view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = coFeeConfig.getFees(address(this));
        return fees.total;
    }
}
