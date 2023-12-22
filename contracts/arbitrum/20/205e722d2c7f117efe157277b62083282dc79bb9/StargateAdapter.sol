//SPDX-License-Identifier: Unlicense
// Creator: Pixel8 Labs
pragma solidity ^0.8.7;

import "./IStargateRouter.sol";
import "./ISushiSwapRouter.sol";
import "./IStargateLPFarming.sol";
import "./IProvider.sol";
import "./ERC20_IERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./AccessControl.sol";

contract StargateAdapter is IProvider, ReentrancyGuard, Ownable, AccessControl {
  using SafeMath for uint256;

  receive() external payable{}
  fallback() external payable{}

  // @notice Constants used in this contract
  uint256 constant MAX_INT = 2**256 - 1;

  // @notice Stargate contract interfaces & pools info
  IStargateRouter public stargateRouter;
  IStargateLPFarming public stargateLPFarming;

  // @notice SushiSwap contract interfaces
  ISushiSwapRouter public sushiSwapRouter;

  // @notice Stargate Pool IDs
  uint16 public stargatePoolID;
  uint256 public farmingPoolID;

  // @notice USDC token interface
  IERC20 public usdc;
  IERC20 public stgLPToken;
  IERC20 public stg;

  // @notice Current deposit fee
  uint256 public override currentDepositFee = 0;

  // @notice Role for settling
  bytes32 public constant SETTLE_ROLE = keccak256('SETTLE_ROLE');
  bytes32 public constant MIGRATE_ROLE = keccak256('MIGRATE_ROLE');
  bytes32 public constant WITHDRAW_ROLE = keccak256('WITHDRAW_ROLE');

  constructor(
    address _routerAddress,
    address _usdcAddress,
    uint16 _poolID,
    address _poolAddress,
    uint256 _farmingPoolId,
    address _lpFarmingAddress,
    address _stgAddress,
    address _sushiswapRouterAddress
  ) {
    // Setup Stargate Router & LP Farming Interface
    stargateRouter = IStargateRouter(_routerAddress);
    stargateLPFarming = IStargateLPFarming(_lpFarmingAddress);

    // Setup SushiSwap Router Interface
    sushiSwapRouter = ISushiSwapRouter(_sushiswapRouterAddress);

    // Setup USDC Interface & approve USDC to be spent by Stargate Router
    usdc = IERC20(_usdcAddress);
    usdc.approve(_routerAddress, MAX_INT);

    // Setup Stargate Pool ID used to deposit USDC
    stargatePoolID = _poolID;
    farmingPoolID = _farmingPoolId;

    // Setup LP Token Interface & approve LP Token to be spent by Stargate LP Farming contract
    stgLPToken = IERC20(_poolAddress);
    stgLPToken.approve(_lpFarmingAddress, MAX_INT);

    // Setup STG Interface
    stg = IERC20(_stgAddress);
    stg.approve(address(sushiSwapRouter), MAX_INT);

    // Setup Default Admin Role
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function stake(address from, uint256 _amountUSDC)
    external
    override
    nonReentrant
  {
    // Transfer USDC from user to contract
    usdc.transferFrom(from, address(this), _amountUSDC);

    // Snapshot Stargate LP token balance before add liquidity
    uint256 prevBalance = stgLPToken.balanceOf(address(this));

    // Update current deposit fee
    currentDepositFee = currentDepositFee.add(_amountUSDC);

    // Deposit USDC to Stargate Pool via Stargate Router
    stargateRouter.addLiquidity(stargatePoolID, _amountUSDC, address(this));

    // Snapshot Stargate LP token balance after add liquidity
    uint256 afterBalance = stgLPToken.balanceOf(address(this));

    // Get exact amount of stgLpToken received after adding liquidity
    uint256 stgLPTokenReceived = afterBalance.sub(prevBalance);

    // Deposit LP token to Stargate LP Farming contract
    stargateLPFarming.deposit(farmingPoolID, stgLPTokenReceived);
  }

  function unstake(address from, uint256 _amountMVLPToken)
    external
    override
    nonReentrant
    returns (uint256)
  {
    // Snapshot Stargate LP token balance before unstake
    uint256 prevBalance = stgLPToken.balanceOf(address(this));

    // Get Exact Amount of STG LP Token to withdraw
    uint256 stgLPContract = stargateLPFarming.userInfo(
      farmingPoolID,
      address(this)
    );
    uint256 amountMVLP = (_amountMVLPToken.mul(stgLPContract)).div(1e6);
    
    // Withdraw LP Token (Stargate) from Stargate LP Farming contract
    stargateLPFarming.withdraw(farmingPoolID, amountMVLP);

    // Snapshot Stargate LP token balance after unstake
    uint256 afterBalance = stgLPToken.balanceOf(address(this));

    // Snapshot USDC balance before remove liquidity
    uint256 prevUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of USDC received after removing liquidity
    uint256 stgLPTokenReceived = afterBalance.sub(prevBalance);

    // Withdraw USDC from Stargate Pool via Stargate Router
    stargateRouter.instantRedeemLocal(
      stargatePoolID,
      stgLPTokenReceived,
      address(this)
    );

    // Snapshot USDC balance after remove liquidity
    uint256 afterUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of USDC transferred to user
    uint256 amountUSDCTransferred = afterUSDCBalance.sub(prevUSDCBalance);

    // Update current deposit fee
    currentDepositFee = currentDepositFee.sub(amountUSDCTransferred);

    // Transfer $USDC to user
    usdc.transfer(from, amountUSDCTransferred);

    return amountUSDCTransferred;
  }

  function claim(address to)
    external
    override
    nonReentrant
    onlyRole(SETTLE_ROLE)
    returns (
      uint256,
      uint256,
      string memory
    )
  {
    // Claim All $STG rewards from Stargate LP Farming contract
    stargateLPFarming.deposit(farmingPoolID, 0);

    // Get STG Balance Contract
    uint256 amountSTG = stg.balanceOf(address(this));

    // Created Path
    address[] memory path = new address[](2);
    path[0] = address(stg);
    path[1] = address(usdc);

    uint256 amountOutMin = sushiSwapRouter.getAmountsOut(amountSTG, path)[1];

    // Execute the Tokens Swap from $STG to $USDC
    sushiSwapRouter.swapExactTokensForTokens(
      amountSTG,
      amountOutMin,
      path,
      to,
      block.timestamp
    );

    return (amountSTG, amountOutMin, 'STG');
  }

  function migrate(address provider)
    external
    override
    nonReentrant
    onlyRole(MIGRATE_ROLE)
    returns (uint256)
  {
    // Get Stargate LP Token Balance
    uint256 stgLPContract = stargateLPFarming.userInfo(
      farmingPoolID,
      address(this)
    );

    // Previous balance of LP Token (Stargate)
    uint256 prevBalance = stgLPToken.balanceOf(address(this));

    // Withdraw LP Token (Stargate) from Stargate LP Farming contract
    stargateLPFarming.withdraw(farmingPoolID, stgLPContract);

    // After balance of LP Token (Stargate)
    uint256 afterBalance = stgLPToken.balanceOf(address(this));

    // Get exact amount of LP Token (Stargate) received after unstake
    uint256 stgLPTokenReceived = afterBalance.sub(prevBalance);

    // Previous balance of USDC Token
    uint256 prevUSDCBalance = usdc.balanceOf(address(this));

    // Withdraw USDC from Stargate Pool via Stargate Router
    stargateRouter.instantRedeemLocal(
      stargatePoolID,
      stgLPTokenReceived,
      address(this)
    );

    // After balance of USDC Token
    uint256 afterUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of USDC transferred to user
    uint256 amountUSDCTransferred = afterUSDCBalance.sub(prevUSDCBalance);

    // Update current deposit fee
    currentDepositFee = 0;

    // Transfer $USDC to provider
    usdc.transfer(provider, amountUSDCTransferred);

    return amountUSDCTransferred;
  }

  function stakeByAdapter(uint256 _amountUSDC) external override {
    // Snapshot Stargate LP token balance before add liquidity
    uint256 prevBalance = stgLPToken.balanceOf(address(this));

    // Update current deposit fee
    currentDepositFee = currentDepositFee.add(_amountUSDC);

    // Deposit USDC to Stargate Pool via Stargate Router
    stargateRouter.addLiquidity(stargatePoolID, _amountUSDC, address(this));

    // Snapshot Stargate LP token balance after add liquidity
    uint256 afterBalance = stgLPToken.balanceOf(address(this));

    // Get exact amount of stgLpToken received after adding liquidity
    uint256 stgLPTokenReceived = afterBalance.sub(prevBalance);

    // Deposit LP token to Stargate LP Farming contract
    stargateLPFarming.deposit(farmingPoolID, stgLPTokenReceived);
  }

  function withdrawERC20(address erc20, address to)
    external
    override
    onlyRole(WITHDRAW_ROLE)
  {
    IERC20 token = IERC20(erc20);
    token.transfer(to, token.balanceOf(address(this)));
  }

  function withdrawETH(address to) external payable override onlyRole(WITHDRAW_ROLE){
    (bool success, ) = payable(to).call{value: address(this).balance}("");
    require(success, "MagicVault: ETH_TRANSFER_FAILED");
  }
}


