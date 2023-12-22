// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/*
#     #    #     #####  ###  #####
##   ##   # #   #     #  #  #     #
# # # #  #   #  #        #  #
#  #  # #     # #  ####  #  #
#     # ####### #     #  #  #
#     # #     # #     #  #  #     #
#     # #     #  #####  ###  #####

#     #    #    #     # #       #######
#     #   # #   #     # #          #
#     #  #   #  #     # #          #
#     # #     # #     # #          #
 #   #  ####### #     # #          #
  # #   #     # #     # #          #
   #    #     #  #####  #######    #
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
    Find more about it in https://treasure.lol and https://thecollectorsnft.xyz/magic-vault
*/
contract MagicVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILPToken;

    IMiniChefV2 public constant MINICHEFV2 = IMiniChefV2(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);
    ISushiSwapRouter public constant SUSHI_ROUTER = ISushiSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IERC20 public constant SUSHI = IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
    IERC20 public constant MAGIC = IERC20(0x539bdE0d7Dbd336b79148AA742883198BBF60342);
    ILPToken public constant LP_TOKEN = ILPToken(0xB7E50106A5bd3Cf21AF210A755F9C8740890A8c9);
    IREWARDER public constant REWARDER = IREWARDER(0x1a9c20e2b0aC11EBECbDCA626BBA566c4ce8e606);
    uint256 public constant POOL_ID = 13; // Magic pool

    address[] public sushiToMagicPath;
    address[] public magicToEthPath;
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
        sushiToMagicPath = [0xd4d42F0b6DEF4CE0383636770eF773390d85c61A, 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0x539bdE0d7Dbd336b79148AA742883198BBF60342];
        magicToEthPath = [0x539bdE0d7Dbd336b79148AA742883198BBF60342, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1];
        SUSHI.approve(address(SUSHI_ROUTER), type(uint256).max);
        MAGIC.approve(address(SUSHI_ROUTER), type(uint256).max);
        LP_TOKEN.approve(address(MINICHEFV2), type(uint256).max);
        devFee = 100;
    }

    function setSushiToMagicPath(address[] memory _sushiToMagicPath) external onlyOwner {
        sushiToMagicPath = _sushiToMagicPath;
    }

    function setDevFee(uint256 _devFee) external onlyOwner {
        require(devFee <= 100, "not cool");
        devFee = _devFee;
    }

    function setMagicToEthPath(address[] memory _magicToEthPath) external onlyOwner {
        magicToEthPath = _magicToEthPath;
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
        // We can use msg.sender because we called updatePool just one sec ago so no magic and sushi rewards
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
        // We can use msg.sender because we called updatePool just one sec ago so no magic and sushi rewards
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
                    sushiToMagicPath,
                    address(this),
                    block.timestamp
                );
            }
            uint256 halfMagicBalance = MAGIC.balanceOf(address(this)) / 2;
            if (halfMagicBalance > 0.0001 ether && totalShares > 0) {
                SUSHI_ROUTER.swapExactTokensForETH(
                    halfMagicBalance,
                    1,
                    magicToEthPath,
                    address(this),
                    block.timestamp
                );
                SUSHI_ROUTER.addLiquidityETH{value : address(this).balance}(
                    address(MAGIC),
                    halfMagicBalance,
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

