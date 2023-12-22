// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeERC20.sol";

abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

pragma solidity >=0.6.0 <0.9.0;

interface IUniswapV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function burn(address to) external returns (uint amount0, uint amount1);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function totalSupply() external view returns (uint256);
    function kLast() external view returns (uint256);
}

interface IUniswapRouterETH {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}


interface IChef {
    function deposit(uint256 _pid, uint256 _amount, address _to) external;

    function withdraw(uint256 _pid, uint256 _amount, address _to) external;

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

    function harvest(uint256 pid, address to) external;

    function userInfo(
        uint256,
        address
    ) external view returns(
        uint256 amount,
        uint256 boostAmount
    );
}

contract FeeManager is Ownable, Pausable {

    struct CommonAddresses {
        address vault;
        address unirouter;
        address keeper;
        address strategist;
        address dinoFeeRecipient;
        address dinoFeeConfig;
    }

    IUniswapRouterETH public unirouter;

    uint256 constant public WITHDRAWAL_FEE_CAP = 50;
    uint256 constant public DINO_FEE_CAP = 1000;
    uint256 constant public WITHDRAWAL_MAX = 10000;
    uint256 internal withdrawalFee = 10;

   // performance fees: 1 -> 1 / 1000
    uint256 public dinoFee = 10;
    
    bool public harvestOnDeposit;

    address public vault;  


    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;
    uint256 public autoMinSwap;

    event SetWithdrawalFee(uint256 withdrawalFee);
    event SetDinoFee(uint256 dinoFee);
    event SetVault(address vault);

    constructor(
        CommonAddresses memory _commonAddresses
    ) {
        vault = _commonAddresses.vault;
        unirouter = IUniswapRouterETH(_commonAddresses.unirouter);
        // keeper = _commonAddresses.keeper;
        // strategist = _commonAddresses.strategist;
    }

    modifier onlyManager() {
        require(msg.sender == owner(), "!manager");
        _;
    }

    function setUnirouter(IUniswapRouterETH _unirouter) external onlyOwner {
        unirouter = _unirouter;
    }

     function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    // adjust withdrawal fee
    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");
        withdrawalFee = _fee;
        emit SetWithdrawalFee(_fee);
    }

    function setDinoFee(uint256 _fee) public onlyManager {
        require(_fee <= DINO_FEE_CAP, "!cap");
        withdrawalFee = _fee;
        emit SetDinoFee(dinoFee);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit, uint256 _autoMinSwap) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        autoMinSwap = _autoMinSwap;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }
}

contract StrategyMasterChef is Ownable, FeeManager {
    using SafeERC20 for IERC20;

    // Tokens used
    IERC20 public want;
    address public native;
    address public output;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    IChef public chef;
    uint256 public poolId;

    uint256 shareTotal;
    uint256 public lastHarvest;

    constructor(
        IChef chef_,
        IERC20 want_,
        uint256 poolId_,
        CommonAddresses memory _commonAddresses,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
        ) FeeManager(_commonAddresses) {
        Ownable.__Ownable_init();
        chef = chef_;
        want = want_;
        poolId = poolId_;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(address(want)).token0();
        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0, "outputToLp0Route[last] != lpToken0");
        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IUniswapV2Pair(address(want)).token1();
        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1, "outputToLp1Route[last] != lpToken1");
        outputToLp1Route = _outputToLp1Route;

        _giveAllowances();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(address(chef), type(uint).max);
        IERC20(output).safeApprove(address(unirouter), type(uint).max);

        IERC20(lpToken0).safeApprove(address(unirouter), 0);
        IERC20(lpToken0).safeApprove(address(unirouter), type(uint).max);

        IERC20(lpToken1).safeApprove(address(unirouter), 0);
        IERC20(lpToken1).safeApprove(address(unirouter), type(uint).max);
    }

    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            chef.deposit(poolId, wantBal, address(this));
        }
        
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        _harvest();

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            chef.withdraw(poolId, _amount - wantBal, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
    }

    function _harvest() internal whenNotPaused {
        chef.harvest(poolId, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees();
            addLiquidity();
            deposit();
            lastHarvest = block.timestamp;
        }
    }

    function chargeFees() internal {
        want.safeTransfer(owner(), want.balanceOf(address(this)) * dinoFee / DINO_FEE_CAP);
    }

    function addLiquidity() internal {
      uint256 outputHalf = IERC20(output).balanceOf(address(this)) / 2;
      if(outputHalf < autoMinSwap || harvestOnDeposit == false) return;
      if (lpToken0 != output) {
          IUniswapRouterETH(unirouter).swapExactTokensForTokens(
              outputHalf, 0, outputToLp0Route, address(this), block.timestamp
          );
      }

      if (lpToken1 != output) {
          IUniswapRouterETH(unirouter).swapExactTokensForTokens(
              outputHalf, 0, outputToLp1Route, address(this), block.timestamp
          );
      }

      uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
      uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
      IUniswapRouterETH(unirouter).addLiquidity(
        lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp
     );
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }
 
    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = chef.userInfo(poolId, address(this));
        return _amount;
    }

}
