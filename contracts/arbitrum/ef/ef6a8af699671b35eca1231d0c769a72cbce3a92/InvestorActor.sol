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
    function check(uint256 id, address usr, uint256 str, address pol, uint256 val, uint256 bor)
        external
        returns (bool ok, uint256 need, uint256 rebate);
}

interface IInvestorActorStrategyProxy {
    function mint(address str, address ast, uint256 amt, bytes calldata dat) external returns (uint256);
    function burn(address str, address ast, uint256 sha, bytes calldata dat) external returns (uint256);
}

contract InvestorActor is Util {
    error GuardNotOk();
    error InsufficientShares();
    error InsufficientBorrow();
    error Undercollateralized();
    error CantBorrowAndDivest();
    error OverMaxBorrowFactor();
    error NoEditingInSameBlock();
    error PositionNotLiquidatable();
    error InsufficientAmountForRepay();
    error PoolOverMaxUtilization();

    IInvestor public investor;
    IInvestorActorStrategyProxy public strategyProxy;
    IGuard public guard;
    IPositionManager public positionManager;
    uint256 public performanceFee = 0.1e4;
    uint256 public originationFee = 0;
    uint256 public liquidationFee = 0.05e4;
    uint256 public softLiquidationSize = 0.5e4;
    uint256 public softLiquidationThreshold = 0.95e18;
    uint256 public poolMaxUtilization = 0.9e18;
    mapping(uint256 => uint256) private lastEditBlock;

    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor(address _investor, address _strategyProxy) {
        investor = IInvestor(_investor);
        strategyProxy = IInvestorActorStrategyProxy(_strategyProxy);
        exec[_investor] = true;
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "performanceFee") performanceFee = data;
        if (what == "originationFee") originationFee = data;
        if (what == "liquidationFee") liquidationFee = data;
        if (what == "softLiquidationSize") softLiquidationSize = data;
        if (what == "softLiquidationThreshold") softLiquidationThreshold = data;
        if (what == "poolMaxUtilization") poolMaxUtilization = data;
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "guard") guard = IGuard(data);
        if (what == "positionManager") positionManager = IPositionManager(data);
        emit File(what, data);
    }

    function life(uint256 id) public view returns (uint256) {
        (,,,,, uint256 sha, uint256 bor) = investor.positions(id);
        return _life(id, sha, bor);
    }

    function _life(uint256 id, uint256 sha, uint256 bor) internal view returns (uint256) {
        (, address pol, uint256 str,,,,) = investor.positions(id);
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
            if (lastEditBlock[id] == block.number) revert NoEditingInSameBlock();
            lastEditBlock[id] = block.number;
        }

        {
            (, address pol, uint256 str,,,,) = investor.positions(id);
            pool = IPool(pol);
            asset = IERC20(pool.asset());
            strategy = IStrategy(investor.strategies(str));
        }

        (,,,,,, uint256 pbor) = investor.positions(id);
        uint256 amt = aamt > 0 ? uint256(aamt) : 0;

        if (abor > 0) {
            bor = int256(pool.borrow(uint256(abor)));
            amt = amt + uint256(abor) - _takeBorrowFee(pool, abor);
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
            asset.transfer(address(strategyProxy), amt);
            sha = int256(strategyProxy.mint(address(strategy), address(asset), amt, dat));
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

        bas = _maybeSetBasisToInitialRate(id, bas, sha, abor);

        _checkLife(id, sha, bor);
    }

    function _borrowValue(IPool pool, uint256 bor) internal view returns (uint256) {
        IOracle oracle = IOracle(pool.oracle());
        uint256 price = (uint256(oracle.latestAnswer()) * 1e18) / (10 ** oracle.decimals());
        uint256 scaled = (bor * 1e18) / (10 ** IERC20(pool.asset()).decimals());
        return (scaled * pool.getUpdatedIndex() / 1e18) * price / 1e18;
    }

    function _takeBorrowFee(IPool pool, int256 abor) internal returns (uint256) {
        if (pool.getUtilization() > poolMaxUtilization) {
            revert PoolOverMaxUtilization();
        }
        // leave in contract, mintProtocolReserves will happen
        return uint256(abor) * originationFee / 10000;
    }

    function _burnShares(uint256 id, int256 aamt, bytes calldata dat) internal returns (uint256) {
        (, address pol, uint256 str,,, uint256 psha,) = investor.positions(id);
        uint256 camt = uint256(0 - aamt);
        if (camt > psha) revert InsufficientShares();
        return strategyProxy.burn(investor.strategies(str), IPool(pol).asset(), camt, dat);
    }

    function _checkGuardAndGetRebate(uint256 id, int256 sha, int256 bor) internal returns (uint256) {
        if (address(guard) == address(0)) return 0;
        uint256 strategyId;
        IPool pool;
        IStrategy strategy;
        {
            (, address pol, uint256 str,,, uint256 psha, uint256 pbor) = investor.positions(id);
            strategyId = str;
            pool = IPool(pol);
            strategy = IStrategy(investor.strategies(str));
            sha = sha + int256(psha);
            bor = bor + int256(pbor);
        }
        (bool ok,, uint256 rebate) = guard.check(
            id,
            _positionOwner(id),
            strategyId,
            address(pool),
            strategy.rate(uint256(sha)),
            _borrowValue(pool, uint256(bor))
        );
        if (!ok) revert GuardNotOk();
        return rebate;
    }

    function _takePerformanceFee(uint256 id, int256 aamt, uint256 amt, uint256 rebate)
        internal
        returns (int256, uint256)
    {
        uint256 fee;
        int256 bas = (aamt > 0 ? aamt : int256(0)) - int256(amt);
        (,,,, uint256 pamt,,) = investor.positions(id);
        int256 namt = int256(pamt) + bas;
        if (namt < 0) {
            fee = uint256(0 - namt) * performanceFee / 10000;
            fee = fee * (1e18 - rebate) / 1e18;
            // leave in contract, mintProtocolReserves will happen
        }
        // Cap bas (basis change) to position size
        if (bas < 0 - int256(pamt)) bas = 0 - int256(pamt);
        return (bas, fee);
    }

    function _maybeSetBasisToInitialRate(uint256 id, int256 bas, int256 sha, int256 abor)
        internal
        view
        returns (int256)
    {
        (, address pol, uint256 str, uint256 out,, uint256 psha,) = investor.positions(id);
        if (out != block.timestamp || psha > 0) return bas;
        IStrategy strategy = IStrategy(investor.strategies(str));
        IOracle oracle = IOracle(IPool(pol).oracle());
        uint256 tokenBasis = 10 ** IERC20(IPool(pol).asset()).decimals();
        uint256 price = (uint256(oracle.latestAnswer()) * 1e18) / (10 ** oracle.decimals());
        uint256 value = strategy.rate(uint256(sha)) * tokenBasis / 1e18;
        return int256(value * 1e18 / price) - abor;
    }

    function _checkLife(uint256 id, int256 sha, int256 bor) internal view {
        (,,,,, uint256 psha, uint256 pbor) = investor.positions(id);
        if (_life(id, uint256(int256(psha) + sha), uint256(int256(pbor) + bor)) < 1e18) {
            revert Undercollateralized();
        }
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
            if (lastEditBlock[id] == block.number) revert NoEditingInSameBlock();
            lastEditBlock[id] = block.number;
        }

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
            amt = strategyProxy.burn(_positionStrategy(id), address(asset), sha, dat);
        }

        // Collect liquidation fee
        // Minting protocol reserves before repay to allow it's use for bad debt
        fee = amt * liquidationFee / 10000;
        uint256 haf = fee / 2;
        if (fee > 0) {
            // Pay keeper
            push(asset, kpr, haf);
            // Pay protocol by minting reserves
            // leave in contract, mintProtocolReserves will happen
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

    function _positionStrategy(uint256 id) internal view returns (address) {
        (,, uint256 str,,,,) = investor.positions(id);
        return investor.strategies(str);
    }

    function _positionOwner(uint256 id) internal view returns (address) {
        (address own,,,,,,) = investor.positions(id);
        if (own == address(positionManager)) {
            own = positionManager.ownerOf(id);
        }
        return own;
    }

    function mintProtocolReserves(address pool) public auth {
        IERC20 asset = IERC20(IPool(pool).asset());
        uint256 amt = IERC20(pool).balanceOf(address(this));
        asset.approve(address(pool), amt);
        IPool(pool).mint(amt, address(0));
    }
}

