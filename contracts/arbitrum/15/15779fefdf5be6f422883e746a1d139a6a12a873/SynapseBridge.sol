// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20.sol";
import "./ERC20Burnable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

import "./ISwap.sol";
import "./IWETH9.sol";

// interface IRouter { 

//   struct Trade {
//         uint256 amountIn;
//         uint256 amountOut;
//         address[] path;
//         address[] adapters;
//   }

//   function selfSwap(
//         Trade calldata _trade,
//         address _to,
//         uint256 _fee
//     ) external returns (uint256);
// }

interface IERC20Mintable is IERC20 {
  function mint(address to, uint256 amount) external;
}

contract SynapseBridge is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;
  using SafeERC20 for IERC20Mintable;
  using SafeMath for uint256;

  bytes32 public constant NODEGROUP_ROLE = keccak256('NODEGROUP_ROLE');
  bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE_ROLE');

  mapping(address => uint256) private fees;

  uint256 public startBlockNumber;
  uint256 public constant bridgeVersion = 6;
  uint256 public chainGasAmount;
  address payable public WETH_ADDRESS;
  address public ROUTER;

  mapping(bytes32 => bool) private kappaMap;

  receive() external payable {}
  
  function initialize() external initializer {
    startBlockNumber = block.number;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    __AccessControl_init();
  }

  function setChainGasAmount(uint256 amount) external {
    require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
    chainGasAmount = amount;
  }

  function setWethAddress(address payable _wethAddress) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
    WETH_ADDRESS = _wethAddress;
  }

  function addKappas(bytes32[] calldata kappas) external {
    require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
    for (uint256 i = 0; i < kappas.length; ++i) {
      kappaMap[kappas[i]] = true;
    }
  }

  function setRouterAddress(address _router) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
    ROUTER = _router;
  }


  event TokenDeposit(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount
  );
  event TokenRedeem(address indexed to, uint256 chainId, IERC20 token, uint256 amount);
  event TokenWithdraw(address indexed to, IERC20 token, uint256 amount, uint256 fee, bytes32 indexed kappa);
  event TokenMint(
    address indexed to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    bytes32 indexed kappa
  );
   event TokenDepositAndSwap(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline
  );
  event TokenMintAndSwap(
    address indexed to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline,
    bool swapSuccess,
    bytes32 indexed kappa
  );
  event TokenRedeemAndSwap(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline
  );
  event TokenRedeemAndRemove(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    uint8 swapTokenIndex,
    uint256 swapMinAmount,
    uint256 swapDeadline
  );
  event TokenWithdrawAndRemove(
    address indexed to,
    IERC20 token,
    uint256 amount,
    uint256 fee,
    uint8 swapTokenIndex,
    uint256 swapMinAmount,
    uint256 swapDeadline,
    bool swapSuccess,
    bytes32 indexed kappa
  );
  event TokenDepositAndSwapV2(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    bytes routeraction
  );
  event TokenMintAndSwapV2(
    address indexed to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    bytes routeraction,
    bool swapSuccess,
    bytes32 indexed kappa
  );
  event TokenRedeemAndSwapV2(
    address indexed to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    bytes routeraction
  );
  event TokenWithdrawAndSwapV2(
    address indexed to,
    IERC20 token,
    uint256 amount,
    uint256 fee,
    bytes routeraction,
    bool swapSuccess,
    bytes32 indexed kappa
  );

  // VIEW FUNCTIONS ***/
  function getFeeBalance(address tokenAddress) external view returns (uint256) {
    return fees[tokenAddress];
  }

  function kappaExists(bytes32 kappa) external view returns (bool) {
    return kappaMap[kappa];
  }

  // FEE FUNCTIONS ***/
  /**
   * * @notice withdraw specified ERC20 token fees to a given address
   * * @param token ERC20 token in which fees acccumulated to transfer
   * * @param to Address to send the fees to
   */
  function withdrawFees(IERC20 token, address to) external whenNotPaused() {
    require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
    require(to != address(0), "Address is 0x000");
    if (fees[address(token)] != 0) {
      token.safeTransfer(to, fees[address(token)]);
      fees[address(token)] = 0;
    }
  }

  // PAUSABLE FUNCTIONS ***/
  function pause() external {
    require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
    _pause();
  }

  function unpause() external {
    require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
    _unpause();
  }


// ******* STANDARD FUNCTIONS 

  /**
   * @notice Relays to nodes to transfers an ERC20 token cross-chain
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   **/
  function deposit(
    address to,
    uint256 chainId,
    IERC20 token,
    uint256 amount
  ) external nonReentrant() whenNotPaused() {
    emit TokenDeposit(to, chainId, token, amount);
    token.safeTransferFrom(msg.sender, address(this), amount);
  }

  /**
   * @notice Relays to nodes to transfers an ERC20 token cross-chain
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   **/
  function depositMax(
    address to,
    uint256 chainId,
    IERC20 token
  ) external nonReentrant() whenNotPaused() {
    uint256 allowance = token.allowance(msg.sender, address(this));
    uint256 tokenBalance = token.balanceOf(msg.sender);
    uint256 amount = (allowance > tokenBalance) ? tokenBalance : allowance;
    emit TokenDeposit(to, chainId, token, amount);
    token.safeTransferFrom(msg.sender, address(this), amount);
  }



  /**
   * @notice Relays to nodes that (typically) a wrapped synAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain
   * @param to address on other chain to redeem underlying assets to
   * @param chainId which underlying chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   **/
  function redeem(
    address to,
    uint256 chainId,
    ERC20Burnable token,
    uint256 amount
  ) external nonReentrant() whenNotPaused() {
    emit TokenRedeem(to, chainId, token, amount);
    token.burnFrom(msg.sender, amount);
  }

  /**
   * @notice Relays to nodes that (typically) a wrapped synAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain
   * @param to address on other chain to redeem underlying assets to
   * @param chainId which underlying chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   **/
    function redeemMax(
    address to,
    uint256 chainId,
    ERC20Burnable token
  ) external nonReentrant() whenNotPaused() {
    uint256 allowance = token.allowance(msg.sender, address(this));
    uint256 tokenBalance = token.balanceOf(msg.sender);
    uint256 amount = (allowance > tokenBalance) ? tokenBalance : allowance;
    emit TokenRedeem(to, chainId, token, amount);
    token.burnFrom(msg.sender, amount);
  }


  /**
   * @notice Function to be called by the node group to withdraw the underlying assets from the contract
   * @param to address on chain to send underlying assets to
   * @param token ERC20 compatible token to withdraw from the bridge
   * @param amount Amount in native token decimals to withdraw
   * @param fee Amount in native token decimals to save to the contract as fees
   * @param kappa kappa
   **/
  function withdraw(
    address to,
    IERC20 token,
    uint256 amount,
    uint256 fee,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);
    if (address(token) == WETH_ADDRESS && WETH_ADDRESS != address(0)) {
      IWETH9(WETH_ADDRESS).withdraw(amount.sub(fee));
      (bool success, ) = to.call{value: amount.sub(fee)}("");
      require(success, "ETH_TRANSFER_FAILED");
      emit TokenWithdraw(to, token, amount, fee, kappa);
    } else {
      emit TokenWithdraw(to, token, amount, fee, kappa);
      token.safeTransfer(to, amount.sub(fee));
    }
  }


  /**
   * @notice Nodes call this function to mint a SynERC20 (or any asset that the bridge is given minter access to). This is called by the nodes after a TokenDepositV2 event is emitted.
   * @dev This means the SynapseBridge.sol contract must have minter access to the token attempting to be minted
   * @param to address on other chain to redeem underlying assets to
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain post-fees
   * @param fee Amount in native token decimals to save to the contract as fees
   * @param kappa kappa
   **/
  function mint(
    address payable to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);
    emit TokenMint(to, token, amount.sub(fee), fee, kappa);
    token.mint(address(this), amount);
    IERC20(token).safeTransfer(to, amount.sub(fee));
    if (chainGasAmount != 0 && address(this).balance > chainGasAmount) {
      to.call.value(chainGasAmount)("");
    }
  }


// ******* V1 FUNCTIONS  

  /**
   * @notice Relays to nodes to both transfer an ERC20 token cross-chain, and then have the nodes execute a swap through a liquidity pool on behalf of the user.
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   * @param tokenIndexFrom the token the user wants to swap from
   * @param tokenIndexTo the token the user wants to swap to
   * @param minDy the min amount the user would like to receive, or revert to only minting the SynERC20 token crosschain.
   * @param deadline latest timestamp to accept this transaction
   **/
  function depositAndSwap(
    address to,
    uint256 chainId,
    IERC20 token,
    uint256 amount,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline
  ) external nonReentrant() whenNotPaused() {
     emit TokenDepositAndSwap(
      to,
      chainId,
      token,
      amount,
      tokenIndexFrom,
      tokenIndexTo,
      minDy,
      deadline
    );
    token.safeTransferFrom(msg.sender, address(this), amount);
  }

  /**
   * @notice Relays to nodes that (typically) a wrapped synAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain. This function indicates to the nodes that they should attempt to redeem the LP token for the underlying assets (E.g "swap" out of the LP token)
   * @param to address on other chain to redeem underlying assets to
   * @param chainId which underlying chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   * @param tokenIndexFrom the token the user wants to swap from
   * @param tokenIndexTo the token the user wants to swap to
   * @param minDy the min amount the user would like to receive, or revert to only minting the SynERC20 token crosschain.
   * @param deadline latest timestamp to accept this transaction
   **/
  function redeemAndSwap(
    address to,
    uint256 chainId,
    ERC20Burnable token,
    uint256 amount,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline
  ) external nonReentrant() whenNotPaused() {
    emit TokenRedeemAndSwap(
      to,
      chainId,
      token,
      amount,
      tokenIndexFrom,
      tokenIndexTo,
      minDy,
      deadline
    );
    token.burnFrom(msg.sender, amount);
  }

  /**
   * @notice Relays to nodes that (typically) a wrapped synAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain. This function indicates to the nodes that they should attempt to redeem the LP token for the underlying assets (E.g "swap" out of the LP token)
   * @param to address on other chain to redeem underlying assets to
   * @param chainId which underlying chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   * @param swapTokenIndex Specifies which of the underlying LP assets the nodes should attempt to redeem for
   * @param swapMinAmount Specifies the minimum amount of the underlying asset needed for the nodes to execute the redeem/swap
   * @param swapDeadline Specificies the deadline that the nodes are allowed to try to redeem/swap the LP token
   **/
  function redeemAndRemove(
    address to,
    uint256 chainId,
    ERC20Burnable token,
    uint256 amount,
    uint8 swapTokenIndex,
    uint256 swapMinAmount,
    uint256 swapDeadline
  ) external nonReentrant() whenNotPaused() {
      emit TokenRedeemAndRemove(
      to,
      chainId,
      token,
      amount,
      swapTokenIndex,
      swapMinAmount,
      swapDeadline
    );
    token.burnFrom(msg.sender, amount);
  }

  /**
   * @notice Nodes call this function to mint a SynERC20 (or any asset that the bridge is given minter access to), and then attempt to swap the SynERC20 into the desired destination asset. This is called by the nodes after a TokenDepositAndSwap event is emitted.
   * @dev This means the BridgeDeposit.sol contract must have minter access to the token attempting to be minted
   * @param to address on other chain to redeem underlying assets to
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain post-fees
   * @param fee Amount in native token decimals to save to the contract as fees
   * @param pool Destination chain's pool to use to swap SynERC20 -> Asset. The nodes determine this by using PoolConfig.sol.
   * @param tokenIndexFrom Index of the SynERC20 asset in the pool
   * @param tokenIndexTo Index of the desired final asset
   * @param minDy Minumum amount (in final asset decimals) that must be swapped for, otherwise the user will receive the SynERC20.
   * @param deadline Epoch time of the deadline that the swap is allowed to be executed.
   * @param kappa kappa
   **/
  function mintAndSwap(
    address payable to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    ISwap pool,
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 minDy,
    uint256 deadline,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);
    // Transfer gas airdrop
    if (chainGasAmount != 0 && address(this).balance > chainGasAmount) {
      to.call.value(chainGasAmount)("");
    }
    // first check to make sure more will be given than min amount required
    uint256 expectedOutput = ISwap(pool).calculateSwap(
      tokenIndexFrom,
      tokenIndexTo,
      amount.sub(fee)
    );

    if (expectedOutput >= minDy) {
      // proceed with swap
      token.mint(address(this), amount);
      token.safeIncreaseAllowance(address(pool), amount);
      try
        ISwap(pool).swap(
          tokenIndexFrom,
          tokenIndexTo,
          amount.sub(fee),
          minDy,
          deadline
        )
      returns (uint256 finalSwappedAmount) {
        // Swap succeeded, transfer swapped asset
        IERC20 swappedTokenTo = ISwap(pool).getToken(tokenIndexTo);
        if (address(swappedTokenTo) == WETH_ADDRESS && WETH_ADDRESS != address(0)) {
          IWETH9(WETH_ADDRESS).withdraw(finalSwappedAmount);
          (bool success, ) = to.call{value: finalSwappedAmount}("");
          require(success, "ETH_TRANSFER_FAILED");
          emit TokenMintAndSwap(to, token, finalSwappedAmount, fee, tokenIndexFrom, tokenIndexTo, minDy, deadline, true, kappa);
        } else {
          swappedTokenTo.safeTransfer(to, finalSwappedAmount);
          emit TokenMintAndSwap(to, token, finalSwappedAmount, fee, tokenIndexFrom, tokenIndexTo, minDy, deadline, true, kappa);
        }
      } catch {
        IERC20(token).safeTransfer(to, amount.sub(fee));
        emit TokenMintAndSwap(to, token, amount.sub(fee), fee, tokenIndexFrom, tokenIndexTo, minDy, deadline, false, kappa);
      }
    } else {
      token.mint(address(this), amount);
      IERC20(token).safeTransfer(to, amount.sub(fee));
      emit TokenMintAndSwap(to, token, amount.sub(fee), fee, tokenIndexFrom, tokenIndexTo, minDy, deadline, false, kappa);
    }
  }

  /**
   * @notice Function to be called by the node group to withdraw the underlying assets from the contract
   * @param to address on chain to send underlying assets to
   * @param token ERC20 compatible token to withdraw from the bridge
   * @param amount Amount in native token decimals to withdraw
   * @param fee Amount in native token decimals to save to the contract as fees
   * @param pool Destination chain's pool to use to swap SynERC20 -> Asset. The nodes determine this by using PoolConfig.sol.
   * @param swapTokenIndex Specifies which of the underlying LP assets the nodes should attempt to redeem for
   * @param swapMinAmount Specifies the minimum amount of the underlying asset needed for the nodes to execute the redeem/swap
   * @param swapDeadline Specificies the deadline that the nodes are allowed to try to redeem/swap the LP token
   * @param kappa kappa
   **/
  function withdrawAndRemove(
    address to,
    IERC20 token,
    uint256 amount,
    uint256 fee,
    ISwap pool,
    uint8 swapTokenIndex,
    uint256 swapMinAmount,
    uint256 swapDeadline,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);
    // first check to make sure more will be given than min amount required
    uint256 expectedOutput = ISwap(pool).calculateRemoveLiquidityOneToken(
      amount.sub(fee),
      swapTokenIndex
    );

    if (expectedOutput >= swapMinAmount) {
      token.safeIncreaseAllowance(address(pool), amount.sub(fee));
      try
        ISwap(pool).removeLiquidityOneToken(
          amount.sub(fee),
          swapTokenIndex,
          swapMinAmount,
          swapDeadline
        )
      returns (uint256 finalSwappedAmount) {
        // Swap succeeded, transfer swapped asset
        IERC20 swappedTokenTo = ISwap(pool).getToken(swapTokenIndex);
        swappedTokenTo.safeTransfer(to, finalSwappedAmount);
        emit TokenWithdrawAndRemove(to, token, finalSwappedAmount, fee, swapTokenIndex, swapMinAmount, swapDeadline, true, kappa);
      } catch {
        IERC20(token).safeTransfer(to, amount.sub(fee));
        emit TokenWithdrawAndRemove(to, token, amount.sub(fee), fee, swapTokenIndex, swapMinAmount, swapDeadline, false, kappa);
      }
    } else {
      token.safeTransfer(to, amount.sub(fee));
      emit TokenWithdrawAndRemove(to, token, amount.sub(fee), fee, swapTokenIndex, swapMinAmount, swapDeadline, false, kappa);
    }
  }


// ******* V2 FUNCTIONS   
  /**
   * @notice Relays to nodes to both transfer an ERC20 token cross-chain, and then have the nodes execute a swap through a liquidity pool on behalf of the user.
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   
   **/
  function depositMaxAndSwapV2(
    address to,
    uint256 chainId,
    IERC20 token,
    bytes calldata routeraction
  ) external nonReentrant() whenNotPaused() {
    uint256 allowance = token.allowance(msg.sender, address(this));
    uint256 tokenBalance = token.balanceOf(msg.sender);
    uint256 amount = (allowance > tokenBalance) ? tokenBalance : allowance;
     emit TokenDepositAndSwapV2(
      to,
      chainId,
      token,
      amount,
      routeraction
    );
    token.safeTransferFrom(msg.sender, address(this), amount);
  }



  /**
   * @notice Relays to nodes that (typically) a wrapped synAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain
   * @param to address on other chain to redeem underlying assets to
   * @param chainId which underlying chain to bridge assets onto
   * @param token ERC20 compatible token to deposit into the bridge
   
   **/
    function redeemMaxAndSwapV2(
    address to,
    uint256 chainId,
    ERC20Burnable token,
    bytes calldata routeraction
  ) external nonReentrant() whenNotPaused() {
    uint256 allowance = token.allowance(msg.sender, address(this));
    uint256 tokenBalance = token.balanceOf(msg.sender);
    uint256 amount = (allowance > tokenBalance) ? tokenBalance : allowance;
    emit TokenRedeemAndSwapV2(to, chainId, token, amount, routeraction);
    token.burnFrom(msg.sender, amount);
  }



  /**
   * @notice Nodes call this function to mint a SynERC20 (or any asset that the bridge is given minter access to), and then attempt to swap the SynERC20 into the desired destination asset. This is called by the nodes after a TokenDepositAndSwapV2 event is emitted.
   * @dev This means the BridgeDeposit.sol contract must have minter access to the token attempting to be minted
   * @param to address on other chain to redeem underlying assets to
   * @param token ERC20 compatible token to deposit into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain post-fees
   * @param fee Amount in native token decimals to save to the contract as fees
    
   * @param kappa kappa
   **/
  function mintAndSwapV2(
    address payable to,
    IERC20Mintable token,
    uint256 amount,
    uint256 fee,
    bytes calldata routeraction,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);
    // Transfer gas airdrop
    if (chainGasAmount != 0 && address(this).balance > chainGasAmount) {
      to.call.value(chainGasAmount)("");
    }
    token.mint(ROUTER, amount);
    (bool success, bytes memory result) = ROUTER.call(routeraction);
    if (success) {  
      // Swap successful
      emit TokenMintAndSwapV2(to, token, amount.sub(fee), fee, routeraction, true, kappa);
    } else {
      IERC20(token).safeTransferFrom(ROUTER, to, amount.sub(fee));
      emit TokenMintAndSwapV2(to, token, amount.sub(fee), fee, routeraction, false, kappa);
    }
    // try IRouter(ROUTER).selfSwap(_trade, to, 0) {
    //   emit TokenMintAndSwapV2(to, token, amount.sub(fee), fee, _trade, true, kappa);
    // } catch {
    //   IERC20(token).safeTransferFrom(ROUTER, to, amount.sub(fee));
    //   emit TokenMintAndSwapV2(to, token, amount.sub(fee), fee, _trade, false, kappa);
    // }
  }

  /**
   * @notice Function to be called by the node group to withdraw the underlying assets from the contract
   * @param to address on chain to send underlying assets to
   * @param token ERC20 compatible token to withdraw from the bridge
   * @param amount Amount in native token decimals to withdraw
   * @param fee Amount in native token decimals to save to the contract as fees
   
   * @param kappa kappa
   **/
  function withdrawAndSwapV2(
    address to,
    IERC20 token,
    uint256 amount,
    uint256 fee,
    bytes calldata routeraction,
    bytes32 kappa
  ) external nonReentrant() whenNotPaused() {
    require(hasRole(NODEGROUP_ROLE, msg.sender), 'Caller is not a node group');
    require(amount > fee, 'Amount must be greater than fee');
    require(!kappaMap[kappa], 'Kappa is already present');
    kappaMap[kappa] = true;
    fees[address(token)] = fees[address(token)].add(fee);

    IERC20(token).safeTransfer(ROUTER, amount.sub(fee));
    (bool success, bytes memory result) = ROUTER.call(routeraction);
     if (success) { 
      // Swap successful
      emit TokenWithdrawAndSwapV2(to, token, amount.sub(fee), fee, routeraction, true, kappa);
    } else {
        IERC20(token).safeTransferFrom(ROUTER, to, amount.sub(fee));
        emit TokenWithdrawAndSwapV2(to, token, amount.sub(fee), fee, routeraction, false, kappa);
    }
    // try IRouter(ROUTER).selfSwap(_trade, to, 0) {
    //   emit TokenWithdrawAndSwapV2(to, token, amount.sub(fee), fee, _trade, true, kappa);
    // } catch {
    //   IERC20(token).safeTransferFrom(ROUTER, to, amount.sub(fee));
    //   emit TokenWithdrawAndSwapV2(to, token, amount.sub(fee), fee, _trade, false, kappa);
    // }
  }
}

