// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";

interface IVesting {
    function vest(address user, address token, uint256 amount, uint256 initial, uint256 time) external;
}

interface IXRDO {
    function mint(uint256 amount, address to) external;
}

// Allows investors to deposit funds once whitelisted and claim tokens at a given price
contract PrivateInvestors is Util {
    error SoldOut();
    error DepositOver();
    error VestingNotStarted();
    error AlreadyClaimed();

    struct Tranche {
        uint256 cap;
        uint256 price;
        uint256 percent;
        uint256 initial;
        uint256 vesting;
    }
    struct User {
        uint256 amount;
        uint256 tranche;
        uint256 price;
        uint256 percent;
        uint256 initial;
        uint256 vesting;
        bool claimed;
    }

    Tranche[4] public tranches;
    IERC20 public paymentToken;
    IERC20 public rdo;
    IERC20 public xrdo;
    IVesting public vester;
    uint256 public depositEnd;
    uint256 public totalUsers;
    uint256 public totalDeposits;
    mapping(address => User) public users;

    event FileInt(bytes32 what, uint256 data);
    event FileAddress(bytes32 what, address data);
    event Deposit(address indexed user, uint256 amount, uint256 tranche);
    event SetUser(address indexed user, uint256 amount, uint256 price, uint256 percent, uint256 initial, uint256 vesting);
    event Vest(address indexed user, uint256 rdoAmount, uint256 xrdoAmount, uint256 initial, uint256 vesting);

    constructor(address _paymentToken, uint256 _depositEnd) {
        tranches[0] = Tranche(250000e6, 0.07e18, 0.5e18, 0.1e18, 6 * 30 days);
        tranches[1] = Tranche(1000000e6, 0.0725e18, 0.5e18, 0.1e18, 6 * 30 days);
        tranches[2] = Tranche(3000000e6, 0.075e18, 0.5e18, 0.1e18, 6 * 30 days);
        tranches[3] = Tranche(10000000e6, 0.08e18, 0.5e18, 0.1e18, 6 * 30 days);
        paymentToken = IERC20(_paymentToken);
        depositEnd = _depositEnd;
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) public auth {
        if (what == "paused") paused = data == 1;
        if (what == "depositEnd") depositEnd = data;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) public auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "rdo") rdo = IERC20(data);
        if (what == "xrdo") xrdo = IERC20(data);
        if (what == "vesting") vester = IVesting(data);
        emit FileAddress(what, data);
    }

    function setTranche(uint256 index, uint256 cap, uint256 price, uint256 percent, uint256 initial, uint256 vesting) public auth {
        tranches[index] = Tranche(cap, price, percent, initial, vesting);
    }

    function setUser(address target, uint256 amount, uint256 price, uint256 percent, uint256 initial, uint256 vesting) public auth {
        if (block.timestamp > depositEnd) revert DepositOver();
        User storage user = users[target];
        if (user.amount == 0) totalUsers += 1;
        uint256 previousAmount = user.amount;
        user.amount = amount;
        user.price = price;
        user.percent = percent;
        user.initial = initial;
        user.vesting = vesting;
        totalDeposits = totalDeposits + amount - previousAmount;
        emit SetUser(target, amount, price, percent, initial, vesting);
    }

    function collect(address token, uint256 amount, address to) public auth {
        IERC20(token).transfer(to, amount);
    }

    function deposit(uint256 amount) public loop live {
        uint256 tranche = type(uint256).max;
        uint256 totalCap;
        for (uint256 i = 0; i < 4; i++) {
            totalCap += tranches[i].cap;
            if (totalDeposits < totalCap) {
                tranche = i;
                break;
            }
        }
        if (tranche == type(uint256).max) revert SoldOut();
        if (block.timestamp > depositEnd) revert DepositOver();
        pull(paymentToken, msg.sender, amount);
        User storage user = users[msg.sender];
        if (user.amount == 0) totalUsers += 1;
        user.amount += amount;
        user.tranche = tranche;
        totalDeposits += amount;
        emit Deposit(msg.sender, amount, tranche);
    }

    function vest(address target) public loop live {
        if (target != msg.sender && !exec[msg.sender]) revert Unauthorized();
        User storage user = users[target];
        if (block.timestamp < depositEnd) revert VestingNotStarted();
        if (user.claimed) revert AlreadyClaimed();
        user.claimed = true;
        uint256 price = user.price;
        if (price == 0) price = tranches[user.tranche].price;
        uint256 amountScaled = user.amount * 1e18 / (10 ** paymentToken.decimals());
        uint256 amount = amountScaled * 1e18 / user.price;
        uint256 rdoAmount = amount * user.percent / 1e18;
        vester.vest(target, address(rdo), rdoAmount, user.initial, user.vesting);
        rdo.approve(address(xrdo), amount - rdoAmount);
        IXRDO(address(xrdo)).mint(amount - rdoAmount, address(this));
        uint256 xrdoAmount = xrdo.balanceOf(address(this));
        xrdo.approve(address(vester), xrdoAmount);
        vester.vest(target, address(xrdo), xrdoAmount, user.initial, user.vesting);
        emit Vest(target, rdoAmount, xrdoAmount, user.initial, user.vesting);
    }

    function getUser(address target) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool) {
        User memory user = users[target];
        Tranche memory tranche = tranches[user.tranche];
        if (user.price == 0) user.price = tranche.price;
        if (user.percent == 0) user.percent = tranche.percent;
        if (user.initial == 0) user.initial = tranche.initial;
        if (user.vesting == 0) user.vesting = tranche.vesting;
        return (user.amount, user.tranche, user.price, user.percent, user.initial, user.vesting, user.claimed);
    }
}

