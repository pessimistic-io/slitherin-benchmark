// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Ownable.sol";

import "./IBinaryConfig.sol";

/// @notice Configuration of Ryze platform
/// @author https://balance.capital
contract BinaryConfig is Ownable, IBinaryConfig {
    uint256 public constant FEE_BASE = 10_000;
    /// @dev Trading fee should be paid when winners claim their rewards, see claim function of Market
    uint256 public tradingFee;
    /// @dev treasury bips
    uint256 public treasuryBips = 3000; // 30%
    /// @dev Max vault risk bips
    uint256 public maxVaultRiskBips = 3000; // 30%
    /// @dev Max vault hourly exposure
    uint256 public maxHourlyExposure = 500; // 5%
    /// @dev Max withdrawal percent for betting available
    uint256 public maxWithdrawalBipsForFutureBettingAvailable = 2_000; // 20%
    uint256 public bettingAmountBips = 5_000; // 50%
    uint256 public futureBettingTimeUpTo = 6 hours;

    uint256 public intervalForExposureUpdate = 1 hours;
    uint256 public multiplier = 100; // 100 based value.

    /// Token Logo
    mapping(address => string) public tokenLogo; // USDT => ...

    /// @dev SVG image template for binary vault image
    string public binaryVaultImageTemplate;
    string public vaultDescription = "Trading your Position";

    /// @dev treasury wallet
    address public treasury;
    address public treasuryForReferrals;

    constructor(
        uint16 tradingFee_,
        address treasury_,
        address treasuryForReferrals_
    ) Ownable() {
        require(tradingFee_ < FEE_BASE, "TOO_HIGH");
        require(treasury_ != address(0), "ZERO_ADDRESS");
        require(treasuryForReferrals_ != address(0), "ZERO_ADDRESS");

        tradingFee = tradingFee_;
        treasury = treasury_;
        treasuryForReferrals = treasuryForReferrals_;
    }

    function setTradingFee(uint256 newTradingFee) external onlyOwner {
        require(newTradingFee < FEE_BASE, "TOO_HIGH");
        tradingFee = newTradingFee;
    }

    function setTreasuryBips(uint256 _bips) external onlyOwner {
        require(_bips < FEE_BASE, "TOO_HIGH");
        treasuryBips = _bips;
    }

    function setMaxVaultRiskBips(uint256 _bips) external onlyOwner {
        require(_bips < FEE_BASE, "TOO_HIGH");
        maxVaultRiskBips = _bips;
    }

    function setMaxHourlyExposure(uint256 _bips) external onlyOwner {
        require(_bips < FEE_BASE, "TOO_HIGH");
        maxHourlyExposure = _bips;
    }

    function setMaxWithdrawalBipsForFutureBettingAvailable(uint256 _bips)
        external
        onlyOwner
    {
        require(_bips < FEE_BASE, "TOO_HIGH");
        maxWithdrawalBipsForFutureBettingAvailable = _bips;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "ZERO_ADDRESS");
        treasury = newTreasury;
    }

    function setTreasuryForReferrals(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "ZERO_ADDRESS");
        treasuryForReferrals = newTreasury;
    }

    function setBettingAmountBips(uint256 _bips) external onlyOwner {
        require(_bips > 0 && _bips <= FEE_BASE, "INVALID_NUMBER");
        bettingAmountBips = _bips;
    }

    function setBinaryVaultImageTemplate(string memory _newValue)
        external
        onlyOwner
    {
        binaryVaultImageTemplate = _newValue;
    }

    function setTokenLogo(address _token, string memory _logo)
        external
        onlyOwner
    {
        tokenLogo[_token] = _logo;
    }

    function setVaultDescription(string memory _desc) external onlyOwner {
        vaultDescription = _desc;
    }

    /**
     * @dev Change future betting allowed time
     */
    function setFutureBettingTimeUpTo(uint256 _time) external onlyOwner {
        require(_time > 0, "INVALID_VALUE");
        futureBettingTimeUpTo = _time;
    }

    function setIntervalForExposureUpdate(uint256 _time) external onlyOwner {
        intervalForExposureUpdate = _time;
    }

    function setMultiplier(uint256 _value) external onlyOwner {
        require(_value < 200 && _value >= 50, "Invalid multiplier");
        multiplier = _value;
    }
}

