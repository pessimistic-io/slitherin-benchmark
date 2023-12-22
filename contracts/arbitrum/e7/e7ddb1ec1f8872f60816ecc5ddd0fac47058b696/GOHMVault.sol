// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/*
                _/_/    _/    _/  _/      _/
     _/_/_/  _/    _/  _/    _/  _/_/  _/_/
  _/    _/  _/    _/  _/_/_/_/  _/  _/  _/
 _/    _/  _/    _/  _/    _/  _/      _/
  _/_/_/    _/_/    _/    _/  _/      _/
     _/
_/_/

  _/      _/    _/_/    _/    _/  _/    _/_/_/_/_/
 _/      _/  _/    _/  _/    _/  _/        _/
_/      _/  _/_/_/_/  _/    _/  _/        _/
 _/  _/    _/    _/  _/    _/  _/        _/
  _/      _/    _/    _/_/    _/_/_/_/  _/
*/

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IMiniChefV2 {
    function harvest(uint256 pid, address to) external;

    function deposit(uint256 pid, uint256 amount, address to) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function userInfo(uint256, address) external view returns (uint256, uint256);
}

interface ISushiSwapRouter {
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IREWARDER {
    function pendingToken(uint256 pid, address user) external view returns (uint256 pendingTokens);
}

interface ILPToken is IERC20 {
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}

/*
    This vault was created for the community by the community.
    Find more about it in https://www.olympusdao.finance/ and https://thecollectorsnft.xyz/values/gOHM
*/
contract GOHMVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILPToken;

    IMiniChefV2 public constant MINICHEFV2 = IMiniChefV2(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);
    ISushiSwapRouter public constant SUSHI_ROUTER = ISushiSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IERC20 public constant SUSHI = IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
    IERC20 public constant gOHM = IERC20(0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1);
    ILPToken public constant LP_TOKEN = ILPToken(0xaa5bD49f2162ffdC15634c87A77AC67bD51C6a6D);
    IREWARDER public constant REWARDER = IREWARDER(0xAE961A7D116bFD9B2534ad27fE4d178Ed188C87A);
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint256 public constant POOL_ID = 12; // gOHM pool

    address[] public sushiTogOHMPath;
    address[] public gOHMToEthPath;
    uint256 public accPerShare;
    uint256 public totalShares;
    mapping(address => uint256) public userShares;
    uint256 public devFee;
    uint256 public lastTimePoolWasAutoCompounded;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event WithdrawAll(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor () {
        sushiTogOHMPath = [address(SUSHI), WETH, address(gOHM)];
        gOHMToEthPath = [address(gOHM), WETH];
        SUSHI.approve(address(SUSHI_ROUTER), type(uint256).max);
        gOHM.approve(address(SUSHI_ROUTER), type(uint256).max);
        LP_TOKEN.approve(address(MINICHEFV2), type(uint256).max);
        devFee = 100;
    }

    function setSushiTogOHMPath(address[] memory _sushiTogOHMPath) external onlyOwner {
        require(_sushiTogOHMPath[0] == address(SUSHI), "First should be sushi");
        require(_sushiTogOHMPath[_sushiTogOHMPath.length - 1] == address(gOHM), "Last should be gOHM");
        sushiTogOHMPath = _sushiTogOHMPath;
    }

    function setDevFee(uint256 _devFee) external onlyOwner {
        require(devFee <= 100, "not cool");
        devFee = _devFee;
    }

    function setgOHMToEthPath(address[] memory _gOHMToEthPath) external onlyOwner {
        require(_gOHMToEthPath[0] == address(gOHM), "First should be gOHM");
        require(_gOHMToEthPath[_gOHMToEthPath.length - 1] == address(WETH), "Last should be WETH");
        gOHMToEthPath = _gOHMToEthPath;
    }

    function doHardWork() nonReentrant public {
        updatePool();
    }

    function balance() public view returns (uint256 _totalLPTokens) {
        (_totalLPTokens,) = MINICHEFV2.userInfo(POOL_ID, address(this));
    }

    function balanceOf(address _user) view public returns (uint256 userBalance) {
        if (totalShares != 0) {
            uint256 pool = balance();
            userBalance = (pool * userShares[_user]) / totalShares;
        } else {
            userBalance = 0;
        }
    }

    function withdrawAll() nonReentrant public {
        require(userShares[msg.sender] > 0, "shares 0");
        updatePool();
        uint256 amount = balanceOf(msg.sender);
        totalShares -= userShares[msg.sender];
        userShares[msg.sender] = 0;
        // We can use msg.sender because we called updatePool just one sec ago so no gOHM and sushi rewards
        MINICHEFV2.withdraw(POOL_ID, amount, msg.sender);
        emit WithdrawAll(msg.sender, amount);
    }

    function withdraw(uint256 _amount) nonReentrant public {
        require(_amount > 0, "amount 0");
        updatePool();
        uint256 pool = balance();
        uint256 sharesToWithdraw = (_amount * totalShares) / pool;
        require(userShares[msg.sender] >= sharesToWithdraw, "Not enough");
        userShares[msg.sender] -= sharesToWithdraw;
        totalShares -= sharesToWithdraw;
        // We can use msg.sender because we called updatePool just one sec ago so no gOHM and sushi rewards
        MINICHEFV2.withdraw(POOL_ID, _amount, msg.sender);
        emit Withdraw(msg.sender, _amount);
    }

    function emergencyWithdraw() nonReentrant public {
        require(userShares[msg.sender] > 0, "shares 0");
        uint256 amount = balanceOf(msg.sender);
        totalShares -= userShares[msg.sender];
        userShares[msg.sender] = 0;
        MINICHEFV2.withdraw(POOL_ID, amount, address(this));
        LP_TOKEN.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    function deposit(uint256 _amount) nonReentrant public {
        require(_amount > 0, "Nothing to deposit");
        updatePool();
        uint256 pool = balance();
        LP_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        MINICHEFV2.deposit(POOL_ID, _amount, address(this));
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount * totalShares) / pool;
        } else {
            currentShares = _amount;
        }
        userShares[msg.sender] += currentShares;
        totalShares += currentShares;
        emit Deposit(msg.sender, _amount);
    }

    function updatePool() internal {
        if (block.timestamp > lastTimePoolWasAutoCompounded) {
            uint256 prevLPBalance = LP_TOKEN.balanceOf(address(this));
            MINICHEFV2.harvest(POOL_ID, address(this));
            uint256 sushiBalance = SUSHI.balanceOf(address(this));
            if (sushiBalance > 0.0001 ether) {
                SUSHI_ROUTER.swapExactTokensForTokens(
                    sushiBalance,
                    1,
                    sushiTogOHMPath,
                    address(this),
                    block.timestamp
                );
            }
            uint256 halfgOHMBalance = gOHM.balanceOf(address(this)) / 2;
            if (halfgOHMBalance > 0.0000000001 ether && totalShares > 0) {
                SUSHI_ROUTER.swapExactTokensForETH(
                    halfgOHMBalance,
                    1,
                    gOHMToEthPath,
                    address(this),
                    block.timestamp
                );
                SUSHI_ROUTER.addLiquidityETH{value : address(this).balance}(
                    address(gOHM),
                    halfgOHMBalance,
                    1,
                    1,
                    address(this),
                    block.timestamp
                );
                uint256 addedLPs = LP_TOKEN.balanceOf(address(this)) - prevLPBalance;
                uint256 devAmount = (addedLPs * devFee) / 1000;
                LP_TOKEN.safeTransfer(owner(), devAmount);
                addedLPs -= devAmount;
                MINICHEFV2.deposit(POOL_ID, addedLPs, address(this));
                lastTimePoolWasAutoCompounded = block.timestamp;
            }
        }
    }

    function salvageTokens(address asset) public onlyOwner {
        uint256 _balance = IERC20(asset).balanceOf(address(this));
        if (_balance > 0) {
            IERC20(asset).safeTransfer(owner(), _balance);
        }
    }

    function salvageETH() public onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            Address.sendValue(payable(owner()), _balance);
        }
    }

    receive() external payable {}
}

