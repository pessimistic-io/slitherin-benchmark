//SPDX-License-Identifier: Unlicense
// Creator: Pixel8 Labs
pragma solidity ^0.8.7;

import "./ISynapseRouter.sol";
import "./ISynapseLPFarming.sol";
import "./ISushiSwapRouter.sol";
import "./IProvider.sol";
import "./ERC20_IERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./AccessControl.sol";

contract SynapseAdapter is IProvider, ReentrancyGuard, Ownable, AccessControl {
  using SafeMath for uint256;

  receive() external payable{}
  fallback() external payable{}

  // @notice Constants used in this contract
  uint256 constant MAX_INT = 2**256 - 1;

  // @notice Synapse contract interfaces
  ISynapseRouter public synapseRouter;
  ISynapseLPFarming public synapseLPFarming;

  // @notice SushiSwap contract interfaces
  ISushiSwapRouter public sushiSwapRouter;

  // @notice Synapse Pool IDs
  uint8 public synapsePoolID;
  uint16 public farmingPoolID;

  // @notice USDC token interface
  IERC20 public usdc;
  IERC20 public synLPToken;
  IERC20 public syn;
  IERC20 public weth;

  // @notice Current deposit fee
  uint256 public override currentDepositFee = 0;

  // @notice Role for settling
  bytes32 public constant SETTLE_ROLE = keccak256('SETTLE_ROLE');
  bytes32 public constant MIGRATE_ROLE = keccak256('MIGRATE_ROLE');
  bytes32 public constant WITHDRAW_ROLE = keccak256('WITHDRAW_ROLE');

  constructor(
    address _routerAddress, //Synapse Router
    address _usdcAddress, // USDC
    uint8 _poolID, // Synapse USDC Pool ID
    address _poolAddress, // Synapse LP Token
    uint16 _farmingPoolId, // Synapse Pool ID
    address _lpFarmingAddress, // Synapse LP Farming (MiniChefV2)
    address _synAddress, // Synapse Token
    address _sushiswapRouterAddress, // SushiSwap Router
    address _wethAddress // WETH
  ) {
    // Setup Synapse Router Interface
    synapseRouter = ISynapseRouter(_routerAddress);
    synapseLPFarming = ISynapseLPFarming(_lpFarmingAddress);

    // Setup SushiSwap Router Interface
    sushiSwapRouter = ISushiSwapRouter(_sushiswapRouterAddress);

    // Setup USDC Interface
    // Approve Synapse Router to spend Adapter's USDC
    usdc = IERC20(_usdcAddress);
    usdc.approve(_routerAddress, MAX_INT);

    // Setup Synapse Pool ID
    synapsePoolID = _poolID;
    farmingPoolID = _farmingPoolId;

    // Setup Synapse LP Token Interface
    // Approve Synapse Router and Synapse LP Farming (MiniChefV2) to spend Adapter's Synapse LP Token
    synLPToken = IERC20(_poolAddress);
    synLPToken.approve(_routerAddress, MAX_INT);
    synLPToken.approve(_lpFarmingAddress, MAX_INT);

    // Setup Synapse Token Interface
    // Approve SushiSwap Router to spend Adapter's Synapse Token
    syn = IERC20(_synAddress);
    syn.approve(address(sushiSwapRouter), MAX_INT);

    // Setup WETH Token Interface
    // Approve SushiSwap Router to spend Adapter's WETH
    weth = IERC20(_wethAddress);
    weth.approve(address(sushiSwapRouter), MAX_INT);

    // Setup roles
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function stake(address from, uint256 _amountUSDC)
    external
    override
    nonReentrant
  {
    // Transfer USDC from user to contract
    usdc.transferFrom(from, address(this), _amountUSDC);

    // Snapshot Synapse LP token balance before add liquidity
    uint256 prevBalance = synLPToken.balanceOf(address(this));

    // Update current deposit fee
    currentDepositFee = currentDepositFee.add(_amountUSDC);

    // Deposit USDC to Snyapse Pool via Snyapse Router
    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 0;
    amounts[1] = _amountUSDC;
    amounts[2] = 0;
    synapseRouter.addLiquidity(amounts, 0, block.timestamp);

    // Snapshot Synapse LP token balance after add liquidity
    uint256 afterBalance = synLPToken.balanceOf(address(this));

    // Get exact amount of Synapse LP Token received after adding liquidity
    uint256 synLPTokenReceived = afterBalance.sub(prevBalance);

    // Deposit Synapse LP Token to Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.deposit(farmingPoolID, synLPTokenReceived, address(this));

    // Claim Synapse Token from Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.harvest(farmingPoolID, address(this));
  }

  function unstake(address from, uint256 _amountMVLPToken)
    external
    override
    nonReentrant
    returns (uint256)
  {
    // Convert Decimal 6 to 18
    uint256 _amountMVLPDecimal = _amountMVLPToken.mul(10**12);

    // Snapshot Synapse LP Token balance before unstake
    uint256 prevBalance = synLPToken.balanceOf(address(this));

    // Get Exact Amount of SYN LP Token to withdraw
    uint256 synLPContract = synapseLPFarming.userInfo(
      farmingPoolID, 
      address(this)
    );
    uint256 amountMVLP = (_amountMVLPDecimal.mul(synLPContract)).div(1e18);

    // Withdraw LP Token (Synapse) from Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.withdrawAndHarvest(
      farmingPoolID,
      amountMVLP,
      address(this)
    );

    // Snapshot Synapse LP Token balance after unstake
    uint256 afterBalance = synLPToken.balanceOf(address(this));

    // Snapshot USDC balance before remove liquidity
    uint256 prevUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of Synapse LP Token received after unstake
    uint256 synLPTokenReceived = afterBalance.sub(prevBalance);

    synapseRouter.removeLiquidityOneToken(
      synLPTokenReceived,
      synapsePoolID,
      0,
      block.timestamp
    );

    // Snapshot USDC balance after remove liquidity
    uint256 afterUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of USDC received after unstake
    uint256 amountUSDCTransferred = afterUSDCBalance.sub(prevUSDCBalance);

    // Update current deposit fee
    currentDepositFee = currentDepositFee.sub(amountUSDCTransferred);

    // Transfer USDC to user
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
    // Claim Synapse Token from Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.harvest(farmingPoolID, address(this));

    // Get SYN Balance Contract
    uint256 amountSYN = syn.balanceOf(address(this));

    /**
     * Swap SYN to USDC
     * @notice Swap SYN to USDC Notes: (SYN -> WETH -> USDC)
     * @notice This way of swapping SYN to USDC is not the best way, but it's the only way to do it for now
     * @notice This is because Synapse Router doesn't have a function to swap SYN to USDC
     * @notice Also Sushiswap Router doesn't have a function to swap SYN to USDC directly on Arbitrum (https://docs.synapseprotocol.com/milestones-and-governance/trade-syn)
     * @notice But somehow, Sushiswap Router support to swap SYN to WETH on Arbitrum.
     * @notice So in this case, we swap SYN to WETH first, then swap WETH to USDC
     * @notice This is not the best way because it might cause slippage.
     */

    // Swap SYN to WETH
    address[] memory path = new address[](2);
    path[0] = address(syn);
    path[1] = address(weth);

    uint256 amountOutMin = sushiSwapRouter.getAmountsOut(amountSYN, path)[1];

    sushiSwapRouter.swapExactTokensForTokens(
      amountSYN,
      amountOutMin,
      path,
      address(this),
      block.timestamp
    );

    uint256 amountWETH = weth.balanceOf(address(this));

    // Swap WETH to USDC
    path = new address[](2);
    path[0] = address(weth);
    path[1] = address(usdc);

    uint256 amountOutMin2 = sushiSwapRouter.getAmountsOut(amountWETH, path)[1];

    sushiSwapRouter.swapExactTokensForTokens(
      amountWETH,
      amountOutMin2,
      path,
      to,
      block.timestamp
    );

    return (amountSYN, 0, 'SYN');
  }

  function migrate(address provider)
    external
    override
    nonReentrant
    onlyRole(MIGRATE_ROLE)
    returns (uint256)
  {
    // Get Synapse LP Token Balance
    uint256 synLPContract = synapseLPFarming.userInfo(
      farmingPoolID,
      address(this)
    );

    // Snapshot Synapse LP Token balance before unstake
    uint256 prevBalance = synLPToken.balanceOf(address(this));

    // Withdraw LP Token (Synapse) from Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.withdrawAndHarvest(
      farmingPoolID,
      synLPContract,
      address(this)
    );

    // Snapshot Synapse LP Token balance after unstake
    uint256 afterBalance = synLPToken.balanceOf(address(this));

    // Get exact amount of Synapse LP Token received after unstake
    uint256 synLPTokenReceived = afterBalance.sub(prevBalance);

    // Snapshot USDC balance before remove liquidity
    uint256 prevUSDCBalance = usdc.balanceOf(address(this));

    synapseRouter.removeLiquidityOneToken(
      synLPTokenReceived,
      synapsePoolID,
      0,
      block.timestamp
    );

    // Snapshot USDC balance after remove liquidity
    uint256 afterUSDCBalance = usdc.balanceOf(address(this));

    // Get exact amount of USDC received after unstake
    uint256 amountUSDCTransferred = afterUSDCBalance.sub(prevUSDCBalance);

    // Update current deposit fee
    currentDepositFee = 0;

    // Transfer $USDC to provider
    usdc.transfer(provider, amountUSDCTransferred);

    return amountUSDCTransferred;
  }

  function stakeByAdapter(uint256 _amountUSDC)
    external
    override
    nonReentrant
    onlyRole(MIGRATE_ROLE)
  {
    // Snapshot Synapse LP token balance before add liquidity
    uint256 prevBalance = synLPToken.balanceOf(address(this));

    // Update current deposit fee
    currentDepositFee = currentDepositFee.add(_amountUSDC);

    // Deposit USDC to Snyapse Pool via Snyapse Router
    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 0;
    amounts[1] = _amountUSDC;
    amounts[2] = 0;
    synapseRouter.addLiquidity(amounts, 0, block.timestamp);

    // Snapshot Synapse LP token balance after add liquidity
    uint256 afterBalance = synLPToken.balanceOf(address(this));

    // Get exact amount of Synapse LP Token received after adding liquidity
    uint256 synLPTokenReceived = afterBalance.sub(prevBalance);

    // Deposit Synapse LP Token to Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.deposit(farmingPoolID, synLPTokenReceived, address(this));

    // Claim Synapse Token from Synapse LP Farming Contract (MiniChefV2)
    synapseLPFarming.harvest(farmingPoolID, address(this));
  }

  function withdrawERC20(address erc20, address to) external override onlyRole(WITHDRAW_ROLE) {
    IERC20 token = IERC20(erc20);
    token.transfer(to, token.balanceOf(address(this)));
  }

  function withdrawETH(address to) external payable override onlyRole(WITHDRAW_ROLE){
    (bool success, ) = payable(to).call{value: address(this).balance}("");
    require(success, "MagicVault: ETH_TRANSFER_FAILED");
  }
}

