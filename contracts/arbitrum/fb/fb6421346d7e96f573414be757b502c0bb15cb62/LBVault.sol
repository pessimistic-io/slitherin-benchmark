// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Math.sol";

import "./LiquidityAmounts.sol";
import "./ILBToken.sol";

import "./ILBStrategy.sol";

/// @title SteakHutLBVaultV1
/// @author SteakHut Finance
contract SteakHutLBVaultV1 is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    uint256 constant PRECISION = 1e18;

    // The last proposed strategy to switch to.
    StratCandidate public stratCandidate;
    // The strategy currently in use by the vault.
    ILBStrategy public strategy;
    // The minimum time that has to pass before a strat candidate can be approved.
    uint256 public immutable approvalDelay;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event Deposit(
        address user,
        uint256 amountX,
        uint256 amountY,
        uint256 shares
    );
    event Withdraw(
        address user,
        uint256 amountX,
        uint256 amountY,
        uint256 shares
    );

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay
    ) ERC20(_name, _symbol) {
        approvalDelay = _approvalDelay;
    }

    /// -----------------------------------------------------------
    /// External / Public Functions
    /// -----------------------------------------------------------

    /// @notice primary entrypoint of funds into the system. users deposit with this function
    /// into the vault. The vault is then in charge of sending funds into the strategy.
    /// funds stay idle in the strategy until earn() is called on the strategy and valid parameters
    /// @notice Deposits tokens in proportion to the vault's current holdings.
    /// @param amountX amount of tokenX to deposit
    /// @param amountY amount of tokenY to deposit
    /// @param amountXMin miniumum amount of tokenX to deposit incl. slippage
    /// @param amountYMin miniumum amount of tokenY to deposit incl. slippage
    /// @return shares minted to the depoositor
    /// @return amountXActual amount token X accepted as deposit
    /// @return amountYActual amount token Y accepted as deposit
    function deposit(
        uint256 amountX,
        uint256 amountY,
        uint256 amountXMin,
        uint256 amountYMin
    )
        external
        nonReentrant
        returns (uint256 shares, uint256 amountXActual, uint256 amountYActual)
    {
        require(amountX > 0 || amountY > 0, "Vault: deposit cannot be 0");

        //harvest any pending rewards to prevent flash theft of yield
        if (totalSupply() != 0) {
            strategy.harvest();
        }

        // Calculate amounts proportional to vault's holdings
        (shares, amountXActual, amountYActual) = calcSharesAndAmounts(
            amountX,
            amountY
        );

        require(shares > 0, "shares");
        require(amountXActual >= amountXMin, "amount0Min");
        require(amountYActual >= amountYMin, "amount1Min");

        //transfer tokens required into the strategy
        if (amountXActual > 0) {
            strategy.tokenX().safeTransferFrom(
                msg.sender,
                address(strategy),
                amountXActual
            );
        }

        if (amountYActual > 0) {
            strategy.tokenY().safeTransferFrom(
                msg.sender,
                address(strategy),
                amountYActual
            );
        }

        //mint vault shares at the required proportion of new liquidity supplied.
        _mint(msg.sender, shares);

        //emit a deposit event
        emit Deposit(msg.sender, amountXActual, amountYActual, shares);
    }

    /// @notice a helper which will withdraw all of the users shares from the vault
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /// @notice primary exit point of funds from the system. users withdraw using this function.
    /// @param _shares amount of shares to withdraw from the system
    /// @return amountX the amount of token X removed
    /// @return amountY the amount of token Y removed
    function withdraw(
        uint256 _shares
    ) public nonReentrant returns (uint256 amountX, uint256 amountY) {
        require(_shares > 0, "Vault: burn 0 not allowed");
        require(_shares <= balanceOf(msg.sender));

        //fetch the total supply of receipt tokens
        uint256 totalSupply = totalSupply();

        //Burn the shares that are being returned
        _burn(msg.sender, _shares);

        // Calculate token amounts proportional to unused balances
        uint256 unusedAmountX = (strategy.getBalanceX() * _shares) /
            totalSupply;
        uint256 unusedAmountY = (strategy.getBalanceY() * _shares) /
            totalSupply;

        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(strategy),
            strategy.strategyActiveBins(),
            address(strategy.lbPair())
        );

        //if liquidity is deployed remove in the correct proportion
        //remove the liquidity in the correct proportion to the shares to be burnt
        uint256 _amountX;
        uint256 _amountY;
        if (totalX > 0 || totalY > 0) {
            uint256 removedDenominator = (PRECISION * totalSupply - 1) /
                _shares +
                1;

            (_amountX, _amountY) = strategy.removeLiquidity(removedDenominator);
        }

        // Sum up total amounts owed to recipient
        amountX = unusedAmountX + _amountX;
        amountY = unusedAmountY + _amountY;

        //transfer tokens back to the user from the strategy
        if (amountX > 0) {
            strategy.tokenX().safeTransferFrom(
                address(strategy),
                address(msg.sender),
                amountX
            );
        }

        if (amountY > 0) {
            strategy.tokenY().safeTransferFrom(
                address(strategy),
                address(msg.sender),
                amountY
            );
        }

        //emit an event
        emit Withdraw(msg.sender, amountX, amountY, _shares);
    }

    /// -----------------------------------------------------------
    /// View functions
    /// -----------------------------------------------------------

    /// @dev Calculates the largest possible `amountx` and `amountY` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amountXDesired` and `amountYDesired` respectively.
    function calcSharesAndAmounts(
        uint256 amountXDesired,
        uint256 amountYDesired
    ) public view returns (uint256 shares, uint256 amountX, uint256 amountY) {
        uint256 totalSupply = totalSupply();

        //add currently active tokens supplied as liquidity
        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(strategy),
            strategy.strategyActiveBins(),
            address(strategy.lbPair())
        );

        //add currently unused tokens in the strategy
        totalX += strategy.getBalanceX();
        totalY += strategy.getBalanceY();

        // If total supply > 0, vault can't be empty
        assert(totalSupply == 0 || totalX > 0 || totalY > 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amountX = amountXDesired;
            amountY = amountYDesired;
            shares = Math.max(amountX, amountY);
        } else if (totalX == 0) {
            amountY = amountYDesired;
            shares = (amountY * totalSupply) / totalY;
        } else if (totalY == 0) {
            amountX = amountXDesired;
            shares = (amountX * totalSupply) / totalX;
        } else {
            uint256 cross = Math.min(
                (amountXDesired * totalY),
                (amountYDesired * totalX)
            );

            require(cross > 0, "cross");

            // Round up amounts
            amountX = (cross - 1) / totalY + 1;
            amountY = (cross - 1) / totalX + 1;
            shares = (cross * totalSupply) / totalX / totalY;
        }
    }

    /// @notice returns the input tokens that may be deposited to this vault
    /// @return tokenX address of first token
    /// @return tokenY address of second token
    function want() external view returns (IERC20, IERC20) {
        return (strategy.tokenX(), strategy.tokenY());
    }

    /// -----------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------

    /// @notice Allows the vaults underlying strategy to be swapped out after first deploy
    /// @param _strategy address of the proposed new strategy.
    function setStrategyAddress(address _strategy) external onlyOwner {
        require(
            address(strategy) == 0x0000000000000000000000000000000000000000,
            "Vault: Strategy already Set"
        );
        strategy = ILBStrategy(_strategy);
        emit UpgradeStrat(_strategy);
    }

    /// @notice Sets the candidate for the new strat to use with this vault.
    /// @param _implementation The address of the candidate strategy.
    function proposeStrat(address _implementation) external onlyOwner {
        require(
            address(this) == ILBStrategy(_implementation).vault(),
            "Proposal not valid for this Vault"
        );

        //check the tokenX and token Y of the proposed strat are the same as the current
        ILBStrategy strategyCurrent = ILBStrategy(strategy);
        ILBStrategy strategyProposed = ILBStrategy(_implementation);
        require(
            strategyCurrent.tokenX() == strategyProposed.tokenX(),
            "Proposal: tokens X not match"
        );

        require(
            strategyCurrent.tokenY() == strategyProposed.tokenY(),
            "Proposal: tokens Y not match"
        );

        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
        });

        emit NewStratCandidate(_implementation);
    }

    /// @notice It switches the active strat for the strat candidate. After upgrading, the
    /// candidate implementation is set to the 0x00 address, and proposedTime to a time
    /// happening in +100 years for safety.
    /// @notice the strategy manager needs to put these funds back to work once completed
    function upgradeStrat() external onlyOwner {
        ILBStrategy _implementation = ILBStrategy(
            stratCandidate.implementation
        );

        require(
            address(_implementation) != address(0),
            "There is no candidate"
        );
        require(
            (stratCandidate.proposedTime + approvalDelay) < block.timestamp,
            "Delay has not passed"
        );

        emit UpgradeStrat(address(_implementation));

        strategy.retireStrat();
        strategy = _implementation;
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        uint256 balanceX = strategy.tokenX().balanceOf(address(this));
        uint256 balanceY = strategy.tokenY().balanceOf(address(this));

        // Push tokens to strategy
        if (balanceX > 0)
            strategy.tokenX().safeTransfer(address(strategy), balanceX);
        if (balanceY > 0)
            strategy.tokenY().safeTransfer(address(strategy), balanceY);
    }

    /// @notice Rescues funds stuck
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /// @notice Rescues LB tokens funds stuck
    /// @param _lbToken address of the token to rescue.
    /// @param _id id of the token to rescue.
    function inCaseLBTokensGetStuck(
        address _lbToken,
        uint256 _id
    ) external onlyOwner {
        uint256 amount = ILBToken(_lbToken).balanceOf(address(this), _id);
        ILBToken(_lbToken).safeTransferFrom(
            address(this),
            msg.sender,
            _id,
            amount
        );
    }

    /// @notice Gets the underlying assets in the vault i.e tokenX and tokenY
    /// includes all tokenX and tokenY idle in the strategy and supplied as liquidity
    /// @param _shares amount of shares
    /// @return totalX amounts of tokenX
    /// @return totalY amounts of tokenY
    function getUnderlyingAssets(
        uint256 _shares
    ) external view returns (uint256 totalX, uint256 totalY) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return (0, 0);
        }

        //add currently active tokens supplied as liquidity
        (totalX, totalY) = LiquidityAmounts.getAmountsOf(
            address(strategy),
            strategy.strategyActiveBins(),
            address(strategy.lbPair())
        );

        //add currently unused tokens in the strategy
        totalX += strategy.getBalanceX();
        totalY += strategy.getBalanceY();

        totalX = (totalX * _shares) / _totalSupply;
        totalY = (totalY * _shares) / _totalSupply;
    }

    /// -----------------------------------------------------------
    /// END
    /// -----------------------------------------------------------
}

