// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {Ownable} from "./Ownable.sol";
import {ERC20, IERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract PeggedFinanceLge is ERC20, Ownable {
    IERC20 public constant PEGG =
        IERC20(0x56fe5AA5692e4FdAB71EA14eF244EEae00F287Be);
    IWETH public constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IRouter constant CAMELOT_ROUTER =
        IRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    IERC20 public immutable PAIR;

    // LGE params
    uint256 public constant PEGG_AMOUNT_FOR_LGE = 5_000_000 * 1e18; // 5,000,000 = 5% of PEGG supply
    uint256 public constant MAX_LAST_BUY_TIMEDELTA = 6 * 60 * 60; // 6 hours

    uint256 public constant STEP1_AMOUNT = 50 * 1e18; // Step1 amount: 50 ETH
    uint256 public constant STEP1_BONUS = 10; // Step1 bonus: 10%

    uint256 public constant STEP2_AMOUNT = 100 * 1e18; // Step2 amount: 100 ETH
    uint256 public constant STEP2_BONUS = 5; // Step2 bonus: 5%

    uint256 constant START_TIMESTAMP = 1683543600; // Date and time (GMT): Monday, 8 May 2023 11:00:00
    uint256 lastBuyTimestamp;
    bool updateLastBuyTimestamp = true;

    // lock params
    uint256 public constant TIME_BEFORE_CLIFF = 60 * 24 * 60 * 60; // 60 days
    uint256 public constant TIME_FOR_LINEAR_UNLOCK = 60 * 24 * 60 * 60; // 60 days
    uint256 public constant INITIAL_UNLOCK = 50; // 50%
    mapping(address => uint256) unlockSpended;

    // referral program
    uint256 public constant REFERRER_LGE_BONUS = 1; // 1% for inviter
    uint256 public constant REFERRAL_LGE_BONUS = 3; // 3% for buyer

    constructor() ERC20("Pegged Finance LGE", "pf.LGE") {
        PAIR = CAMELOT_ROUTER.factory().createPair(PEGG, WETH);
    }

    receive() external payable {
        WETH.deposit{value: msg.value}();
        _buy(msg.value, address(0));
    }

    function buyETH(address referrer) external payable {
        WETH.deposit{value: msg.value}();
        _buy(msg.value, referrer);
    }

    function buyWETH(uint256 amount, address referrer) external {
        WETH.transferFrom(msg.sender, address(this), amount);
        _buy(amount, referrer);
    }

    function claimPEGG(uint256 minAmount) external returns (uint256) {
        uint256 peggAmount = PEGG.balanceOf(address(this));
        uint256 lpBalance = PAIR.balanceOf(address(this));
        uint256 amountToUnlock = unlockedAmount(msg.sender);
        uint256 lpForUser = (lpBalance * amountToUnlock) / totalSupply();

        _burn(msg.sender, amountToUnlock);

        // burn user lp tokens
        PAIR.approve(address(CAMELOT_ROUTER), lpForUser);
        (, uint256 wethAmount) = CAMELOT_ROUTER.removeLiquidity(
            PEGG,
            WETH,
            lpForUser,
            0,
            0,
            address(this),
            block.timestamp
        );

        // swap WETH from burned lp tokens for PEGG
        WETH.approve(address(CAMELOT_ROUTER), wethAmount);
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(PEGG);
        CAMELOT_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethAmount,
            0,
            path,
            address(this),
            address(0),
            block.timestamp
        );

        // return PEGG to user
        peggAmount = PEGG.balanceOf(address(this)) - peggAmount;
        require(peggAmount > minAmount, "Slippage");
        PEGG.transfer(msg.sender, peggAmount);

        return peggAmount;
    }

    // read functions
    function lgeStart() public pure returns (uint256) {
        return START_TIMESTAMP;
    }

    function lgeEnd() public view returns (uint256) {
        if (lastBuyTimestamp == 0) {
            return type(uint256).max;
        }
        return lastBuyTimestamp + MAX_LAST_BUY_TIMEDELTA;
    }

    function timeBeforeLgeStart() public view returns (uint256) {
        return _timeBefore(lgeStart());
    }

    function timeBeforeLgeEnd() public view returns (uint256) {
        return _timeBefore(lgeEnd());
    }

    function unlockedAmount(address user) public view returns (uint256) {
        uint256 startUnlockTs = lastBuyTimestamp + TIME_BEFORE_CLIFF;
        uint256 endUnlockTs = startUnlockTs + TIME_FOR_LINEAR_UNLOCK;
        uint256 userAmount = balanceOf(user);

        if (block.timestamp < startUnlockTs) {
            return 0;
        } else if (block.timestamp > endUnlockTs) {
            return userAmount;
        } else {
            uint256 fullUnlockDuration = endUnlockTs - startUnlockTs;
            uint256 currentDuration = block.timestamp - startUnlockTs;
            uint256 unlockedPercent = INITIAL_UNLOCK +
                (currentDuration * 100) /
                fullUnlockDuration;

            uint256 unlockedForUser = (userAmount * unlockedPercent) / 100;
            uint256 unlockSpendedForUser = unlockSpended[user];
            if (unlockSpendedForUser >= unlockedForUser) {
                return 0;
            } else {
                return unlockedForUser - unlockSpendedForUser;
            }
        }
    }

    // service functions
    function rescueTokens(IERC20 token) external onlyOwner {
        SafeERC20.safeTransfer(token, owner(), token.balanceOf(address(this)));
    }

    function emergencyStop() external onlyOwner {
        updateLastBuyTimestamp = !updateLastBuyTimestamp;
    }

    function provideLiquidity() external onlyOwner lgeEnded {
        uint256 wethBalance = WETH.balanceOf(address(this));
        PEGG.approve(address(CAMELOT_ROUTER), PEGG_AMOUNT_FOR_LGE);
        WETH.approve(address(CAMELOT_ROUTER), wethBalance);
        CAMELOT_ROUTER.addLiquidity(
            PEGG,
            WETH,
            PEGG_AMOUNT_FOR_LGE,
            wethBalance,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // internal logic
    function _afterTokenTransfer(
        address from,
        address,
        uint256 amount
    ) internal override {
        unlockSpended[from] += amount;
    }

    function _buy(uint256 ethAmount, address referrer) internal lgeEnabled {
        if (updateLastBuyTimestamp) {
            lastBuyTimestamp = block.timestamp;
        }

        uint256 userBonus = _getLgeBonus(ethAmount, referrer != address(0));
        uint256 userAmount = (ethAmount * (100 + userBonus)) / 100;

        uint256 referrerBonus = referrer != address(0) ? REFERRER_LGE_BONUS : 0;
        uint256 referrerAmount = (ethAmount * referrerBonus) / 100;

        uint256 protocolAmount = 2 * ethAmount - userAmount - referrerAmount;

        _mint(msg.sender, userAmount);
        _mint(address(this), protocolAmount);
        if (referrerAmount > 0) {
            _mint(referrer, referrerAmount);
        }
    }

    function _getLgeBonus(
        uint256 amount,
        bool referred
    ) internal view returns (uint256 bonus) {
        uint256 wethAmountBeforeBuy = WETH.balanceOf(address(this)) - amount;

        if (wethAmountBeforeBuy < STEP1_AMOUNT) {
            bonus += STEP1_BONUS;
        } else if (wethAmountBeforeBuy < STEP2_AMOUNT) {
            bonus += STEP2_BONUS;
        }

        if (referred) {
            bonus += REFERRAL_LGE_BONUS;
        }
    }

    function _timeBefore(uint256 eventTs) internal view returns (uint256) {
        return block.timestamp > eventTs ? 0 : eventTs - block.timestamp;
    }

    // modifiers
    modifier lgeEnabled() {
        require(timeBeforeLgeStart() == 0, "LGE not started");
        require(timeBeforeLgeEnd() > 0, "LGE ended");
        _;
    }

    modifier lgeEnded() {
        require(timeBeforeLgeEnd() == 0, "LGE not ended yet");
        _;
    }
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IRouter {
    function factory() external view returns (IFactory);

    function addLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;
}

interface IFactory {
    function createPair(
        IERC20 tokenA,
        IERC20 tokenB
    ) external returns (IERC20 pair);
}

