// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SafeMath.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSet.sol";
import "./ITruefiDesk.sol";
import "./ConfigHelper.sol";
import "./AlloyxConfig.sol";
import "./AdminUpgradeable.sol";

/**
 * @title TruefiDesk
 * @notice NAV or statistics related to assets managed for Truefi, the managed portfolios are contracts in Truefi, in here, we take portfolio with USDC as base token
 * @author AlloyX
 */
contract TruefiDesk is ITruefiDesk, AdminUpgradeable {
  using SafeMath for uint256;
  using ConfigHelper for AlloyxConfig;
  using EnumerableSet for EnumerableSet.AddressSet;
  AlloyxConfig public config;
  EnumerableSet.AddressSet managedPortfolioAddresses;
  event AlloyxConfigUpdated(address indexed who, address configAddress);

  function initialize(address _configAddress) external initializer {
    __AdminUpgradeable_init(msg.sender);
    config = AlloyxConfig(_configAddress);
  }

  /**
   * @notice If user operation is paused
   */
  modifier isPaused() {
    require(config.isPaused(), "all user operations should be paused");
    _;
  }

  /**
   * @notice Update configuration contract address
   */
  function updateConfig() external onlyAdmin isPaused {
    config = AlloyxConfig(config.configAddress());
    emit AlloyxConfigUpdated(msg.sender, address(config));
  }

  /**
   * @notice Get the Usdc value of the truefi wallet
   */
  function getTruefiWalletUsdcValue() external view override returns (uint256) {
    uint256 length = managedPortfolioAddresses.length();
    uint256 allBalance = 0;
    for (uint256 i = 0; i < length; i++) {
      uint256 balance = getTruefiWalletUsdcValueOfPortfolio(managedPortfolioAddresses.at(i));
      allBalance += balance;
    }
    return allBalance;
  }

  /**
   * @notice Get the Usdc value of the truefi wallet on one portfolio address
   * @param _address the address of managed portfolio
   */
  function getTruefiWalletUsdcValueOfPortfolio(address _address) public view returns (uint256) {
    IManagedPortfolio managedPortfolio = IManagedPortfolio(_address);
    uint256 portfolioNav = managedPortfolio.value();
    uint256 totalSupply = managedPortfolio.totalSupply();
    uint256 balanceOfWallet = managedPortfolio.balanceOf(config.treasuryAddress());
    return balanceOfWallet.mul(portfolioNav).div(totalSupply);
  }

  /**
   * @notice Add managed portfolio address to the list
   * @param _address the address of managed portfolio
   */
  function addManagedPortfolioAddress(address _address) external onlyAdmin {
    require(!managedPortfolioAddresses.contains(_address), "the address already inside the list");
    IManagedPortfolio managedPortfolio = IManagedPortfolio(_address);
    require(
      managedPortfolio.balanceOf(config.treasuryAddress()) > 0,
      "the balance of the treasury on the portfolio should not be 0 before adding"
    );
    managedPortfolioAddresses.add(_address);
  }

  /**
   * @notice Remove managed portfolio address to the list
   * @param _address the address of managed portfolio
   */
  function removeManagedPortfolioAddress(address _address) external onlyAdmin {
    require(managedPortfolioAddresses.contains(_address), "the address should be inside the list");
    IManagedPortfolio managedPortfolio = IManagedPortfolio(_address);
    require(
      managedPortfolio.balanceOf(config.treasuryAddress()) == 0,
      "the balance of the treasury on the portfolio should be 0 before removing"
    );
    managedPortfolioAddresses.remove(_address);
  }

  /**
   * @notice Deposit treasury USDC to truefi managed portfolio
   * @param _address the address of managed portfolio
   * @param _amount the amount to deposit
   */
  function depositToTruefi(address _address, uint256 _amount) external onlyAdmin {
    bytes memory emptyData;
    IManagedPortfolio managedPortfolio = IManagedPortfolio(_address);
    config.getTreasury().transferERC20(config.usdcAddress(), address(this), _amount);
    config.getUSDC().approve(_address, _amount);
    managedPortfolio.deposit(_amount, emptyData);
    uint256 balance = managedPortfolio.balanceOf(address(this));
    managedPortfolio.transfer(config.treasuryAddress(), balance);
    if (!managedPortfolioAddresses.contains(_address)) {
      managedPortfolioAddresses.add(_address);
    }
  }

  /**
   * @notice Withdraw USDC from truefi managed portfolio and deposit to treasury
   * @param _address the address of managed portfolio
   * @param _amount the amount to withdraw in ManagedPortfolio tokens
   */
  function withdrawFromTruefi(address _address, uint256 _amount)
    external
    onlyAdmin
    returns (uint256)
  {
    bytes memory emptyData;
    IManagedPortfolio managedPortfolio = IManagedPortfolio(_address);
    config.getTreasury().transferERC20(_address, address(this), _amount);
    uint256 usdcAmount = managedPortfolio.withdraw(_amount, emptyData);
    config.getUSDC().transfer(config.treasuryAddress(), usdcAmount);
    if (managedPortfolio.balanceOf(config.treasuryAddress()) == 0) {
      managedPortfolioAddresses.remove(_address);
    }
    return usdcAmount;
  }
}

