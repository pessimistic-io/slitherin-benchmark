// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable.sol";

import "./IBinaryConfig.sol";

/// @notice Configuration of Ryze platform
/// @author https://balance.capital
contract BinaryConfig is Ownable, IBinaryConfig {
    uint256 public constant FEE_BASE = 10_000;
    /// @dev Trading fee should be paid when winners claim their rewards, see claim function of Market
    uint256 public tradingFee;
    /// @dev treasury wallet
    address public treasury;
    /// @dev treasury bips
    uint256 public treasuryBips = 3000; // 30%

    /// @dev Max vault risk bips
    uint256 public maxVaultRiskBips = 3000; // 30%
    /// @dev Max vault hourly exposure
    uint256 public maxHourlyExposure = 500; // 5%
    /// @dev Max withdrawal percent for betting available
    uint256 public maxWithdrawalBipsForFutureBettingAvailable = 2_000; // 20%

    uint256 public futureBettingTimeUpTo = 6 hours;

    /// @dev SVG image template for binary vault image
    string public binaryVaultImageTemplate;
    /// Token Logo
    mapping(address => string) public tokenLogo; // USDT => ...

    string public vaultDescription = "Trading your Position";

    constructor(uint16 tradingFee_, address treasury_) Ownable() {
        require(tradingFee_ < FEE_BASE, "TOO_HIGH");
        require(treasury_ != address(0), "ZERO_ADDRESS");
        tradingFee = tradingFee_;
        treasury = treasury_;
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
}

