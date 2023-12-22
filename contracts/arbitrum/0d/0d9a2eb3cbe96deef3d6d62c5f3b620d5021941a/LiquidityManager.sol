// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { Multicall } from "./Multicall.sol";
import { Payment } from "./Payment.sol";
import { CallbackValidation } from "./CallbackValidation.sol";
import { SafeTransferLib } from "./libraries_SafeTransferLib.sol";
import { LendgineAddress } from "./LendgineAddress.sol";

import { Lendgine } from "./Lendgine.sol";
import { Pair } from "./Pair.sol";

import { PRBMathUD60x18 } from "./PRBMathUD60x18.sol";
import { PRBMath } from "./PRBMath.sol";

/// @notice Wraps Numoen liquidity positions
/// @author Kyle Scott (https://github.com/numoen/manager/blob/master/src/LiquidityManager.sol)
/// @author Modified from Uniswap
/// (https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol)
contract LiquidityManager is Multicall, Payment {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Mint(address indexed operator, uint256 indexed tokenID, uint256 liquidity, uint256 amount0, uint256 amount1);

    event IncreaseLiquidity(uint256 indexed tokenID, uint256 liquidity, uint256 amount0, uint256 amount1);

    event DecreaseLiquidity(uint256 indexed tokenID, uint256 liquidity);

    event Collect(uint256 indexed tokenID, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PositionInvalidError();

    error LivelinessError();

    error SlippageError();

    error UnauthorizedError();

    error CollectError();

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Position {
        uint256 liquidity;
        uint256 rewardPerLiquidityPaid;
        uint256 tokensOwed;
        uint80 lendgineID;
        address operator;
    }

    mapping(address => uint80) private _lendgineIDs;

    mapping(uint80 => LendgineAddress.LendgineKey) private _lendgineIDToLendgineKey;

    mapping(uint256 => Position) private _positions;

    uint176 private _nextID = 1;

    uint80 private _nextLendgineID = 1;

    /*//////////////////////////////////////////////////////////////
                           LIVELINESS MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier checkDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert LivelinessError();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _factory, address _weth9) Payment(_weth9) {
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY MANAGER LOGIC
    //////////////////////////////////////////////////////////////*/

    struct MintParams {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 liquidity;
        address recipient;
        uint256 deadline;
    }

    /// @notice Mint a new liquidity provider position by depositing to the underlying lendgine
    function mint(MintParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 tokenID)
    {
        tokenID = _nextID++;
        LendgineAddress.LendgineKey memory lendgineKey = LendgineAddress.LendgineKey({
            base: params.base,
            speculative: params.speculative,
            baseScaleFactor: params.baseScaleFactor,
            speculativeScaleFactor: params.speculativeScaleFactor,
            upperBound: params.upperBound
        });

        address lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );
        address pair = LendgineAddress.computePairAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );

        (uint256 r0, uint256 r1) = (Pair(pair).reserve0(), Pair(pair).reserve1());
        uint256 _totalSupply = Pair(pair).totalSupply();
        uint256 amount0;
        uint256 amount1;
        if (_totalSupply == 0) {
            amount0 = params.amount0Min;
            amount1 = params.amount1Min;
        } else {
            amount0 = PRBMath.mulDiv(r0, params.liquidity, _totalSupply);
            amount1 = PRBMath.mulDiv(r1, params.liquidity, _totalSupply);
        }
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert SlippageError();

        pay(params.base, msg.sender, pair, amount0);
        pay(params.speculative, msg.sender, pair, amount1);

        Pair(pair).mint(params.liquidity);
        Lendgine(lendgine).deposit(address(this));

        uint80 lendgineID = cacheLendgineKey(lendgine, lendgineKey);
        (, uint256 rewardPerLiquidityPaid, ) = Lendgine(lendgine).positions(address(this));

        _positions[tokenID] = Position({
            operator: params.recipient,
            lendgineID: lendgineID,
            liquidity: params.liquidity,
            rewardPerLiquidityPaid: rewardPerLiquidityPaid,
            tokensOwed: 0
        });

        emit Mint(params.recipient, tokenID, params.liquidity, amount0, amount1);
    }

    struct IncreaseLiquidityParams {
        uint256 tokenID;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 liquidity;
        uint256 deadline;
    }

    /// @notice Increase the size of an already existing liquidity position
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
    {
        Position storage position = _positions[params.tokenID];

        if (msg.sender != position.operator) revert UnauthorizedError();
        if (position.lendgineID == 0) revert PositionInvalidError();

        LendgineAddress.LendgineKey memory lendgineKey = _lendgineIDToLendgineKey[position.lendgineID];

        address lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound
        );
        address pair = LendgineAddress.computePairAddress(
            factory,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound
        );

        (uint256 r0, uint256 r1) = (Pair(pair).reserve0(), Pair(pair).reserve1());
        uint256 _totalSupply = Pair(pair).totalSupply();
        uint256 amount0;
        uint256 amount1;

        amount0 = PRBMath.mulDiv(r0, params.liquidity, _totalSupply);
        amount1 = PRBMath.mulDiv(r1, params.liquidity, _totalSupply);

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert SlippageError();

        pay(lendgineKey.base, msg.sender, pair, amount0);
        pay(lendgineKey.speculative, msg.sender, pair, amount1);

        Pair(pair).mint(params.liquidity);
        Lendgine(lendgine).deposit(address(this));

        (, uint256 rewardPerLiquidityPaid, ) = Lendgine(lendgine).positions(address(this));

        position.tokensOwed += PRBMathUD60x18.mul(
            position.liquidity,
            rewardPerLiquidityPaid - position.rewardPerLiquidityPaid
        );
        position.rewardPerLiquidityPaid = rewardPerLiquidityPaid;
        position.liquidity += params.liquidity;

        emit IncreaseLiquidity(params.tokenID, params.liquidity, amount0, amount1);
    }

    struct DecreaseLiquidityParams {
        uint256 tokenID;
        uint256 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Decrease the size of an already existing liquidity position
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
    {
        Position storage position = _positions[params.tokenID];

        if (msg.sender != position.operator) revert UnauthorizedError();
        if (position.lendgineID == 0) revert PositionInvalidError();

        address recipient = params.recipient == address(0) ? address(this) : params.recipient;
        LendgineAddress.LendgineKey memory lendgineKey = _lendgineIDToLendgineKey[position.lendgineID];

        address lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound
        );
        address pair = LendgineAddress.computePairAddress(
            factory,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound
        );

        Lendgine(lendgine).withdraw(params.liquidity);
        (uint256 amount0Out, uint256 amount1Out) = Pair(pair).burn(recipient, params.liquidity);

        if (amount0Out < params.amount0Min) revert SlippageError();
        if (amount1Out < params.amount1Min) revert SlippageError();

        (, uint256 rewardPerLiquidityPaid, ) = Lendgine(lendgine).positions(address(this));

        position.tokensOwed += PRBMathUD60x18.mul(
            position.liquidity,
            rewardPerLiquidityPaid - position.rewardPerLiquidityPaid
        );
        position.rewardPerLiquidityPaid = rewardPerLiquidityPaid;
        position.liquidity -= params.liquidity;

        emit DecreaseLiquidity(params.tokenID, params.liquidity);
    }

    struct CollectParams {
        uint256 tokenID;
        address recipient;
        uint256 amountRequested;
    }

    /// @notice Collect interest owed to a liquidity provider position
    function collect(CollectParams calldata params) external payable returns (uint256 amount) {
        Position storage position = _positions[params.tokenID];

        if (msg.sender != position.operator) revert UnauthorizedError();
        if (position.lendgineID == 0) revert PositionInvalidError();

        address recipient = params.recipient == address(0) ? address(this) : params.recipient;
        LendgineAddress.LendgineKey memory lendgineKey = _lendgineIDToLendgineKey[position.lendgineID];

        address lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound
        );

        Lendgine(lendgine).accruePositionInterest();
        (, uint256 rewardPerLiquidityPaid, ) = Lendgine(lendgine).positions(address(this));

        position.tokensOwed += PRBMathUD60x18.mul(
            position.liquidity,
            rewardPerLiquidityPaid - position.rewardPerLiquidityPaid
        );
        position.rewardPerLiquidityPaid = rewardPerLiquidityPaid;

        amount = params.amountRequested > position.tokensOwed ? position.tokensOwed : params.amountRequested;
        position.tokensOwed -= amount;

        uint256 amountSent = Lendgine(lendgine).collect(recipient, amount);
        if (amountSent < amount) revert CollectError();

        emit Collect(params.tokenID, amount);
    }

    struct SkimParams {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
        address recipient;
    }

    /// @notice Collects any funds that have been donated to the corresponding pair contract
    function skim(SkimParams calldata params) external payable {
        address pair = LendgineAddress.computePairAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );

        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Pair(pair).skim(recipient);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function cacheLendgineKey(address lendgine, LendgineAddress.LendgineKey memory lendgineKey)
        private
        returns (uint80 lendgineID)
    {
        lendgineID = _lendgineIDs[lendgine];
        if (lendgineID == 0) {
            _lendgineIDs[lendgine] = (lendgineID = _nextLendgineID++);
            _lendgineIDToLendgineKey[lendgineID] = lendgineKey;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Return information for a given position
    function getPosition(uint256 tokenID)
        external
        view
        returns (
            address operator,
            address base,
            address speculative,
            uint256 baseScaleFactor,
            uint256 speculativeScaleFactor,
            uint256 upperBound,
            uint256 liquidity,
            uint256 rewardPerLiquidityPaid,
            uint256 tokensOwed
        )
    {
        Position memory position = _positions[tokenID];
        if (position.lendgineID == 0) revert PositionInvalidError();
        LendgineAddress.LendgineKey memory lendgineKey = _lendgineIDToLendgineKey[position.lendgineID];
        return (
            position.operator,
            lendgineKey.base,
            lendgineKey.speculative,
            lendgineKey.baseScaleFactor,
            lendgineKey.speculativeScaleFactor,
            lendgineKey.upperBound,
            position.liquidity,
            position.rewardPerLiquidityPaid,
            position.tokensOwed
        );
    }
}

