// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";

interface IVester {
    function vest(address user, address token, uint256 amount, uint256 initial, uint256 time) external;
}

interface IXRDO {
    function mint(uint256 amount, address to) external;
}

// Allows investors to deposit funds once whitelisted and claim tokens at a given price
contract PrivateInvestors is Util {
    error OverCap();
    error SoldOut();
    error NoAmount();
    error DepositOver();
    error VestingNotStarted();
    error AlreadyClaimed();
    error NotWhitelisted();

    struct User {
        uint256 amount;
        bool claimed;
    }

    IERC20 public paymentToken;
    IERC20 public rdo;
    IERC20 public xrdo;
    IVester public vester;
    IERC20 public rbcNft;
    uint256 public rbcCap;
    uint256 public rbcStart;
    uint256 public depositEnd;
    uint256 public depositCap;
    uint256 public price;
    uint256 public percent;
    uint256 public initial;
    uint256 public vesting;
    uint256 public totalUsers;
    uint256 public totalDeposits;
    mapping(address => User) public users;
    mapping(address => uint256) public whitelist;

    event FileInt(bytes32 what, uint256 data);
    event FileAddress(bytes32 what, address data);
    event Deposit(address indexed user, uint256 amount);
    event SetUser(address indexed user, uint256 amount);
    event Vest(address indexed user, uint256 rdoAmount, uint256 xrdoAmount);

    constructor(address _paymentToken, uint256 _depositEnd) {
        paymentToken = IERC20(_paymentToken);
        depositEnd = _depositEnd;
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) public auth {
        if (what == "paused") paused = data == 1;
        if (what == "depositEnd") depositEnd = data;
        if (what == "depositCap") depositCap = data;
        if (what == "rbcCap") rbcCap = data;
        if (what == "rbcStart") rbcStart = data;
        if (what == "price") price = data;
        if (what == "percent") percent = data;
        if (what == "initial") initial = data;
        if (what == "vesting") vesting = data;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) public auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "rdo") rdo = IERC20(data);
        if (what == "xrdo") xrdo = IERC20(data);
        if (what == "vester") vester = IVester(data);
        if (what == "rbcNft") rbcNft = IERC20(data);
        emit FileAddress(what, data);
    }

    function setUser(address target, uint256 amount) public auth {
        if (block.timestamp > depositEnd) revert DepositOver();
        User storage user = users[target];
        if (user.amount == 0) totalUsers += 1;
        uint256 previousAmount = user.amount;
        user.amount = amount;
        totalDeposits = totalDeposits + amount - previousAmount;
        emit SetUser(target, amount);
    }

    function setWhitelist(address[] calldata targets, uint256 cap) external auth {
        for (uint256 i = 0; i < targets.length; i++) {
            whitelist[targets[i]] = cap;
        }
    }

    function collect(address token, uint256 amount, address to) external auth {
        IERC20(token).transfer(to, amount);
    }

    function deposit(uint256 amount) external loop live {
        uint256 cap = getCap(msg.sender);
        if (cap == 0) revert NotWhitelisted();
        if (totalDeposits + amount > depositCap) revert SoldOut();
        if (block.timestamp > depositEnd) revert DepositOver();
        pull(paymentToken, msg.sender, amount);
        User storage user = users[msg.sender];
        if (user.amount == 0) totalUsers += 1;
        totalDeposits += amount;
        user.amount += amount;
        if (user.amount > cap) revert OverCap();
        emit Deposit(msg.sender, amount);
    }

    function vest(address target) external loop live {
        if (target != msg.sender && !exec[msg.sender]) revert Unauthorized();
        User storage user = users[target];
        if (block.timestamp < depositEnd) revert VestingNotStarted();
        if (user.amount > 0) revert NoAmount();
        if (user.claimed) revert AlreadyClaimed();
        user.claimed = true;
        uint256 amountScaled = user.amount * 1e18 / (10 ** paymentToken.decimals());
        uint256 amount = amountScaled * 1e18 / price;
        uint256 rdoAmount = amount * percent / 1e18;
        vester.vest(target, address(rdo), rdoAmount, initial, vesting);
        rdo.approve(address(xrdo), amount - rdoAmount);
        IXRDO(address(xrdo)).mint(amount - rdoAmount, address(this));
        uint256 xrdoAmount = xrdo.balanceOf(address(this));
        xrdo.approve(address(vester), xrdoAmount);
        vester.vest(target, address(xrdo), xrdoAmount, initial, vesting);
        emit Vest(target, rdoAmount, xrdoAmount);
    }

    function getCap(address target) public view returns (uint256) {
        uint256 cap = whitelist[target];
        if (cap == 0
            && block.timestamp > rbcStart
            && address(rbcNft) != address(0)
            && rbcNft.balanceOf(target) > 0) {
            cap = rbcCap;
        }
        return cap;
    }

    function getUser(address target) external view returns (uint256, uint256, bool) {
        User memory user = users[target];
        return (user.amount, getCap(target), user.claimed);
    }
}

