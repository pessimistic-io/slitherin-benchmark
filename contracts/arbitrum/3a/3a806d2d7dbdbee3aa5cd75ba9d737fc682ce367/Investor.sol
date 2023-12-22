// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IPool} from "./IPool.sol";
import {IStrategy} from "./IStrategy.sol";
import {IInvestorActor} from "./IInvestorActor.sol";

contract Investor is Util {
    error WrongStatus();
    error InvalidPool();
    error InvalidStrategy();
    error PositionClosed();
    error StrategyIndexToHigh();
    error Undercollateralized();

    struct Position {
        address owner;
        address pool;
        uint256 strategy;
        uint256 outset;
        uint256 amount;
        uint256 shares;
        uint256 borrow;
    }

    uint256 public constant S_PAUSE = 1;
    uint256 public constant S_LIQUIDATE = 2;
    uint256 public constant S_WITHDRAW = 3;
    uint256 public constant S_LIVE = 4;
    uint256 public status;
    uint256 public nextStrategy;
    uint256 public nextPosition;
    IInvestorActor public actor;
    mapping(address => bool) public pools;
    mapping(uint256 => address) public strategies;
    mapping(uint256 => Position) public positions;

    event FileInt(bytes32 indexed what, uint256 data);
    event FileAddress(bytes32 indexed what, address data);
    event SetStrategy(uint256 indexed idx, address old, address str);
    event Edit(uint256 indexed id, int256 amt, int256 bor, int256 sha, int256 bar);
    event Kill(uint256 indexed id, address indexed kpr, uint256 amt, uint256 bor, uint256 fee);

    constructor() {
        status = S_LIVE;
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "status") status = data;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "pools") pools[data] = !pools[data];
        if (what == "actor") actor = IInvestorActor(data);
        emit FileAddress(what, data);
    }

    function setStrategy(uint256 idx, address str) external auth {
        if (idx > nextStrategy) revert StrategyIndexToHigh();
        if (idx == nextStrategy) {
            strategies[idx] = str;
            nextStrategy++;
            emit SetStrategy(idx, address(0), str);
            return;
        }
        IStrategy old = IStrategy(strategies[idx]);
        old.exit(str);
        IStrategy(str).move(address(old));
        strategies[idx] = str;
        emit SetStrategy(idx, address(old), str);
    }

    // Calculates position health (<1e18 is liquidatable)
    function life(uint256 id) public view returns (uint256) {
        return actor.life(id);
    }

    // Invest in strategy, providing collateral and optionally borrowing for leverage
    function earn(address usr, address pol, uint256 str, uint256 amt, uint256 bor, bytes calldata dat)
        external
        loop
        returns (uint256)
    {
        if (status < S_LIVE) revert WrongStatus();
        if (!pools[pol]) revert InvalidPool();
        if (strategies[str] == address(0)) revert InvalidStrategy();
        uint256 id = nextPosition++;
        Position storage p = positions[id];
        p.owner = usr;
        p.pool = pol;
        p.strategy = str;
        p.outset = block.timestamp;
        pullTo(IERC20(IPool(p.pool).asset()), msg.sender, address(actor), uint256(amt));
        (int256 bas, int256 sha, int256 bar) = actor.edit(id, int256(amt), int256(bor), dat);
        p.amount = uint256(bas);
        p.shares = uint256(sha);
        p.borrow = uint256(bar);
        if (actor.life(id) < 1e18) revert Undercollateralized();
        emit Edit(id, int256(amt), int256(bor), sha, bar);
        return id;
    }

    // Modify a position. Positive amt is tokens to invest, negative is shares to divest. Positive bor is asset to borrow, negative is borrow shares to repay.
    function edit(uint256 id, int256 amt, int256 bor, bytes calldata dat) external loop {
        Position storage p = positions[id];
        if (p.owner != msg.sender) revert Unauthorized();
        if (p.shares == 0) revert PositionClosed();
        if (amt >= 0 && status < S_LIVE) revert WrongStatus();
        if (amt < 0 && status < S_WITHDRAW) revert WrongStatus();
        if (amt > 0) pullTo(IERC20(IPool(p.pool).asset()), msg.sender, address(actor), uint256(amt));
        (int256 bas, int256 sha, int256 bar) = actor.edit(id, amt, bor, dat);
        p.amount = uint256(int256(p.amount) + bas);
        p.shares = uint256(int256(p.shares) + sha);
        p.borrow = uint256(int256(p.borrow) + bar);
        if (actor.life(id) < 1e18) revert Undercollateralized();
        emit Edit(id, amt, bor, sha, bar);
    }

    // Liquidate position with health <1e18
    function kill(uint256 id, bytes calldata dat) external loop {
        if (status < S_LIQUIDATE) revert WrongStatus();
        (uint256 sha, uint256 bor, uint256 amt, uint256 fee, uint256 bal) = actor.kill(id, dat, msg.sender);
        Position storage p = positions[id];
        p.shares = p.shares - sha;
        p.borrow = p.borrow - bor;
        emit Kill(id, msg.sender, amt, bal, fee);
    }
}

