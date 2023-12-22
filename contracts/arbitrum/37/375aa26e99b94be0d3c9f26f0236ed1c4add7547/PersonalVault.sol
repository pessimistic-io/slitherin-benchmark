// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./FullMath.sol";
import "./IPersonalVault.sol";
import "./IPerpetualVault.sol";
import "./IHypervisor.sol";
import "./IManager.sol";

import "./console.sol";

interface IERC20Metadata is IERC20 {
  function decimals() external view returns (uint8);
}

/**
 * @notice
 *  Vault contract that receives hypervisor token together with hedge token
 *  stake hypervisor token and long/short with hedge token
 */
contract PersonalVault {
  using SafeERC20 for IERC20Metadata;
  
  uint256 public constant PRECISION = 1e36;

  IManager public manager;
  uint256 public vaultId;
  IHypervisor public hypervisor;
  IERC20Metadata hedgeToken;
  address public strategy;
  address public keeper;
  IPerpetualVault public perpVault;

  uint256 public lookback;
  uint256 hedgeFactor = 10;             // 2 = 50% pricipal, 10 = 10% prinicpal required, etc
  
  uint256 public totalAmount;           // total amount of hypervisor token

  modifier onlyOwner() {
    require(manager.ownerOf(vaultId) == msg.sender, "!owner");
    _;
  }

  modifier onlyKeeper() {
    require(msg.sender == keeper, "!keeper");
    _;
  }

  function initialize(
    uint256 _vaultId,
    address _keeper,
    address _strategy,
    address _hypervisor,
    address _hedgeToken,
    bytes memory/* _config */
  ) external {
    vaultId = _vaultId;
    require(_hypervisor != address(0), "zero address");
    hypervisor = IHypervisor(_hypervisor);
    require(_strategy != address(0), "zero address");
    strategy = _strategy;
    require(_keeper != address(0), "zero address");
    keeper = _keeper;
    require(_hedgeToken == hypervisor.token0() || _hedgeToken == hypervisor.token1(), "invalid hedge token");
    hedgeToken = IERC20Metadata(_hedgeToken);
    lookback = 12;
    hedgeFactor = 10;
    manager = IManager(msg.sender);
    perpVault = IPerpetualVault(manager.perpVaults(_hypervisor));

    hedgeToken.safeApprove(address(perpVault), type(uint256).max);
  }

  /**
   * @notice deposit hypervisor token together with hedge token
   * @param amount amount of hypervisor token
   */
  function deposit(uint256 amount) external onlyOwner {
    uint256 hedgeAmount = _getRequiredHedgeAmount(amount);
    require(hedgeAmount > 0, "too small amount");

    hypervisor.transferFrom(msg.sender, address(this), amount);
    totalAmount = totalAmount + amount;
    hedgeToken.safeTransferFrom(msg.sender, address(this), hedgeAmount);
    perpVault.deposit(hedgeAmount);
  }

  /**
   * @notice
   *  withdraw hypervisor token together with hedge token
   * @param recipient address to receive tokens
   * @param amount amount of hypervisor token to withdraw
   */
  function withdraw(address recipient, uint256 amount) external onlyOwner {
    require(recipient != address(0), "zero address");
    require(amount <= totalAmount, "exceed balance");
    if (amount == 0) {
      amount = totalAmount;
    }
    require(amount != 0, "zero amount");
    uint256 shares = perpVault.shares(address(this)) * amount / totalAmount;
    bool hedgeWithdrawn = perpVault.withdraw(shares);
    hypervisor.transfer(recipient, amount);
    totalAmount = totalAmount - amount;
    if (hedgeWithdrawn) {
      hedgeToken.safeTransfer(recipient, hedgeToken.balanceOf(address(this)));
    }
  }

  /**
   * @notice
   *  called only by perpVault
   */
  function withdrawCallback(address recipient) external {
    require(msg.sender == address(perpVault), "invalid caller");
    hedgeToken.safeTransfer(recipient, hedgeToken.balanceOf(address(this)));
  }

  /**
   * @notice
   *  This is an automation task that is triggered by chainlink keeper.
   */
  function run() external onlyKeeper {
    /* hypervisor token staking and compounding logic */
  }

  function prepareBurn() external { }

  //////////////////////////////
  ////    View Functions    ////
  //////////////////////////////

  function getLpValueInToken1() public view returns(uint256) {
    (uint256 token0, uint256 token1) = hypervisor.getTotalAmounts();
    uint256 totalValue = token0 * getPriceToken0InToken1() + token1 * PRECISION;
    return totalValue / hypervisor.totalSupply();
  }

  function getPriceToken1InToken0() public view returns (uint256) {
    uint256 priceToken0InToken1 = getPriceToken0InToken1();
    require(priceToken0InToken1 != 0, "pool unstable");
    return PRECISION * PRECISION / priceToken0InToken1;
  }

  function getPriceToken0InToken1() public view returns (uint256) {
    (uint160 sqrtPrice, , , , , , ) = hypervisor.pool().slot0();
    uint256 price = FullMath.mulDiv(uint256(sqrtPrice) * uint256(sqrtPrice), PRECISION, 2**(96 * 2));
    return price;
  }

  function estimatedTotalAsset() external view returns (uint256) {}

  //////////////////////////////////
  ////    Internal Functions    ////
  //////////////////////////////////

  function _getRequiredHedgeAmount(uint256 _amount) internal view returns (uint256) {
    address token0 = hypervisor.token0();
    address token1 = hypervisor.token1();
    uint256 decimals0 = IERC20Metadata(token0).decimals();
    uint256 decimals1 = IERC20Metadata(token1).decimals();
    (uint256 token0Amount, uint256 token1Amount) = hypervisor.getTotalAmounts();
    uint256 token0Price = manager.getTokenPrice(token0);
    uint256 token1Price = manager.getTokenPrice(token1);
    uint256 hedgePrice = manager.getTokenPrice(address(hedgeToken));
    uint256 lpValue = (uint256(token0Price) * token0Amount * PRECISION / 10**decimals0 + uint256(token1Price) * token1Amount * PRECISION / 10**decimals1) * _amount / hypervisor.totalSupply();
    uint256 requiredHedgeValue = lpValue / hedgeFactor / PRECISION;
    uint256 hedgeAmount = requiredHedgeValue * 10**hedgeToken.decimals() / uint256(hedgePrice);
    return hedgeAmount;
  }
}

