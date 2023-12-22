// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IPool} from "./IPool.sol";
import {IOracle} from "./IOracle.sol";
import {IStrategy} from "./IStrategy.sol";
import {IInvestor} from "./IInvestor.sol";
import {IPositionManager} from "./IPositionManager.sol";

interface IGuard {
    function check(address usr, address str, address pol, uint256 val, uint256 bor)
      external view returns (bool ok, uint256 need, uint256 rebate);
}

contract InvestorActor is Util {
    error GuardNotOk(uint256 need);
    error WaitBeforeSelling();
    error InsufficientShares();
    error InsufficientBorrow();
    error CantBorrowAndDivest();
    error OverMaxBorrowFactor();
    error PositionNotLiquidatable();
    error InsufficientAmountForRepay();

    IInvestor public investor;
    IGuard public guard;
    IPositionManager public positionManager;
    uint256 public performanceFee = 0.1e4;
    uint256 public originationFee = 0;
    uint256 public liquidationFee = 0.05e4;
    uint256 public softLiquidationSize = 0.5e4;
    uint256 public softLiquidationThreshold = 0.95e18;

    event FileInt(bytes32 indexed what, uint256 data);
    event FileAddress(bytes32 indexed what, address data);

    constructor(address _investor) {
        investor = IInvestor(_investor);
        exec[_investor] = true;
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "performanceFee") performanceFee = data;
        if (what == "originationFee") originationFee = data;
        if (what == "liquidationFee") liquidationFee = data;
        if (what == "softLiquidationSize") softLiquidationSize = data;
        if (what == "softLiquidationThreshold") softLiquidationThreshold = data;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "guard") guard = IGuard(data);
        if (what == "positionManager") positionManager = IPositionManager(data);
        emit FileAddress(what, data);
    }

    function life(uint256 id) public view returns (uint256) {
        (, address pol, uint256 str,,, uint256 sha, uint256 bor) = investor.positions(id);
        IPool pool = IPool(pol);
        if (bor == 0) return 1e18;
        uint256 value = (IStrategy(investor.strategies(str)).rate(sha) * pool.liquidationFactor()) / 1e18;
        uint256 borrow = _borrowValue(pool, bor);
        return value * 1e18 / borrow;
    }

    function edit(uint256 id, int256 aamt, int256 abor, bytes calldata dat)
        public
        auth
        returns (int256 bas, int256 sha, int256 bor)
    {
        IPool pool;
        IERC20 asset;
        IStrategy strategy;
        {
            (, address pol, uint256 str, uint256 out,,,) = investor.positions(id);
            if (out == block.timestamp && aamt < 0) revert WaitBeforeSelling();
            pool = IPool(pol);
            asset = IERC20(pool.asset());
            strategy = IStrategy(investor.strategies(str));
        }

        (,,,,,, uint256 pbor) = investor.positions(id);
        uint256 amt = aamt > 0 ? uint256(aamt) : 0;

        if (abor > 0) {
            bor = int256(pool.borrow(uint256(abor)));
            amt = amt + uint256(abor) - _takeBorrowFee(abor, address(pool));
        }

        if (aamt < 0) {
            sha = aamt;
            amt = amt + _burnShares(id, aamt, dat);
        }

        if (abor < 0) {
            bor = abor;
            uint256 cbor = uint256(0 - abor);
            if (cbor > pbor) revert InsufficientBorrow();
            uint256 rep = cbor * pool.getUpdatedIndex() / 1e18;
            // Check repay amount because if we just call repay with
            // too little funds the pool will try to use protocol reserves
            if (amt < rep) revert InsufficientAmountForRepay();
            asset.approve(address(pool), amt);
            amt = amt - pool.repay(cbor);
        }

        // Make sure whenever a user borrows, all funds go into a strategy
        // if we didn't users could withdraw borrow to their wallet
        if (abor > 0 && aamt < 0) revert CantBorrowAndDivest();
        // We could provide more capital and not borrow or provide no capital and borrow more,
        // but as long as we are not divesting shares or repaying borrow,
        // let's mint more shares with all we got
        if (abor > 0 || aamt > 0) {
            asset.approve(address(strategy), amt);
            sha = int256(strategy.mint(address(asset), amt, dat));
            amt = 0;
        }

        // If the new position amount is below zero, collect a performance fee
        // on that portion of the outgoing assets
        {
            uint256 fee;
            uint256 rebate = _checkGuardAndGetRebate(id, sha, bor);
            (bas, fee) = _takePerformanceFee(id, aamt, amt, rebate);
            amt = amt - fee;
        }

        // Send extra funds to use (if there's any)
        // Happens when divesting or borrowing (and not minting more shares)
        {
            (address own,,,,,,) = investor.positions(id);
            push(asset, own, amt);
        }

        bas = _maybeSetBasisToInitialRate(id, bas, sha);
    }

    function _borrowValue(IPool pool, uint256 bor) internal view returns (uint256) {
        IOracle oracle = IOracle(pool.oracle());
        uint256 price = (uint256(oracle.latestAnswer()) * 1e18) / (10 ** oracle.decimals());
        uint256 scaled = (bor * 1e18) / (10 ** IERC20(pool.asset()).decimals());
        return (scaled * pool.getUpdatedIndex() / 1e18) * price / 1e18;
    }

    function _takeBorrowFee(int256 abor, address pool) internal returns (uint256) {
        uint256 borfee = uint256(abor) * originationFee / 10000;
        if (borfee > 0) {
            IERC20(IPool(pool).asset()).approve(address(pool), borfee);
            IPool(pool).mint(borfee, address(0));
        }
        return borfee;
    }

    function _burnShares(uint256 id, int256 aamt, bytes calldata dat) internal returns (uint256) {
        (, address pol, uint256 str,,, uint256 psha,) = investor.positions(id);
        uint256 camt = uint256(0 - aamt);
        if (camt > psha) revert InsufficientShares();
        return IStrategy(investor.strategies(str)).burn(IPool(pol).asset(), camt, dat);
    }

    function _checkGuardAndGetRebate(uint256 id, int256 sha, int256 bor) internal view returns (uint256) {
        if (address(guard) == address(0)) return 0;
        IPool pool;
        IStrategy strategy;
        {
            (, address pol, uint256 str,,, uint256 psha, uint256 pbor) = investor.positions(id);
            pool = IPool(pol);
            strategy = IStrategy(investor.strategies(str));
            sha = sha + int256(psha);
            bor = bor + int256(pbor);
        }
        (bool ok, uint256 need, uint256 rebate) = guard.check(
          _positionOwner(id), address(strategy), address(pool), strategy.rate(uint256(sha)),
          _borrowValue(pool, uint256(bor)));
        if (!ok) revert GuardNotOk(need);
        return rebate;
    }

    function _takePerformanceFee(uint256 id, int256 aamt, uint256 amt, uint256 rebate) internal returns (int256, uint256) {
        uint256 fee;
        int256 bas = (aamt > 0 ? aamt : int256(0)) - int256(amt);
        (, address pol,,, uint256 pamt,,) = investor.positions(id);
        int256 namt = int256(pamt) + bas;
        if (namt < 0) {
            fee = uint256(0 - namt) * performanceFee / 10000;
            fee = fee * (1e18 - rebate) / 1e18;
            IERC20(IPool(pol).asset()).approve(pol, fee);
            IPool(pol).mint(fee, address(0));
        }
        // Cap bas (basis change) to position size
        if (bas < 0-int256(pamt)) bas = 0-int256(pamt);
        return (bas, fee);
    }

    function _maybeSetBasisToInitialRate(uint256 id, int256 bas, int256 sha) internal view returns (int256) {
        (,address pol, uint256 str, uint256 out,,uint256 psha,) = investor.positions(id);
        if (out != block.timestamp || psha > 0) return bas;
        IStrategy strategy = IStrategy(investor.strategies(str));
        IOracle oracle = IOracle(IPool(pol).oracle());
        uint256 tokenBasis = 10 ** IERC20(IPool(pol).asset()).decimals();
        uint256 price = (uint256(oracle.latestAnswer()) * 1e18) / (10 ** oracle.decimals());
        uint256 value = strategy.rate(uint256(sha)) * tokenBasis / 1e18;
        return int256(value * 1e18 / price);
    }

    function kill(uint256 id, bytes calldata dat, address kpr)
        external
        auth
        returns (uint256 sha, uint256 bor, uint256 amt, uint256 fee, uint256 bal)
    {
        IPool pool;
        IERC20 asset;
        uint256 lif = life(id);

        {
            if (lif >= 1e18) revert PositionNotLiquidatable();
            address pol;
            (, pol,,,, sha,) = investor.positions(id);
            pool = IPool(pol);
            asset = IERC20(pool.asset());
            // Burn maximum amount of strategy shares
            if (lif > softLiquidationThreshold) {
                sha = sha * softLiquidationSize / 10000;
            }
        }

        {
            (,, uint256 str,,,,) = investor.positions(id);
            amt = IStrategy(investor.strategies(str)).burn(address(asset), sha, dat);
        }

        // Collect liquidation fee
        // Minting protocol reserves before repay to allow it's use for bad debt
        fee = amt * liquidationFee / 10000;
        uint256 haf = fee / 2;
        if (fee > 0) {
            // Pay keeper
            push(asset, kpr, haf);
            // Pay protocol by minting reserves
            asset.approve(address(pool), fee - haf);
            pool.mint(fee - haf, address(0));
        }

        {
            (,,,,,, bor) = investor.positions(id);
            // Repay loan
            if (lif > softLiquidationThreshold) {
                bor = min(bor, (amt - fee) * 1e18 / pool.getUpdatedIndex());
            }
            asset.approve(address(pool), amt - fee);
            bal = pool.repay(bor);
            if (amt - fee - bal > 0) {
                push(asset, _positionOwner(id), amt - fee - bal);
            }
        }
    }

    function _positionOwner(uint256 id) internal view returns (address) {
        (address own,,,,,,) = investor.positions(id);
        if (own == address(positionManager)) {
            own = positionManager.ownerOf(id);
        }
        return own;
    }
}

