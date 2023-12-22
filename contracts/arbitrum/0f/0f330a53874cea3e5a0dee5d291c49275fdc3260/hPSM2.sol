// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./fxToken.sol";

/*                                                *\
 *                ,.-"""-.,                       *
 *               /   ===   \                      *
 *              /  =======  \                     *
 *           __|  (o)   (0)  |__                  *
 *          / _|    .---.    |_ \                 *
 *         | /.----/ O O \----.\ |                *
 *          \/     |     |     \/                 *
 *          |                   |                 *
 *          |                   |                 *
 *          |                   |                 *
 *          _\   -.,_____,.-   /_                 *
 *      ,.-"  "-.,_________,.-"  "-.,             *
 *     /          |       |  ╭-╮     \            *
 *    |           l.     .l  ┃ ┃      |           *
 *    |            |     |   ┃ ╰━━╮   |           *
 *    l.           |     |   ┃ ╭╮ ┃  .l           *
 *     |           l.   .l   ┃ ┃┃ ┃  | \,         *
 *     l.           |   |    ╰-╯╰-╯ .l   \,       *
 *      |           |   |           |      \,     *
 *      l.          |   |          .l        |    *
 *       |          |   |          |         |    *
 *       |          |---|          |         |    *
 *       |          |   |          |         |    *
 *       /"-.,__,.-"\   /"-.,__,.-"\"-.,_,.-"\    *
 *      |            \ /            |         |   *
 *      |             |             |         |   *
 *       \__|__|__|__/ \__|__|__|__/ \_|__|__/    *
\*                                                 */

/** @dev Differences from hPSM v1: 
 *         - Fixes deposit amount and renames deposit mapping.
 *         - Does not include the IHandle component.
 *           There is no fxToken validation as this contract is intended to be
 *           deployable to mainnet where there is no IHandle-compatible contract.
 *         - Allows moving liquidity out via a PCT address.
 */
contract hPSM2 is Ownable {
    using SafeERC20 for ERC20;

    /** @dev This contract's address. */
    address private immutable self;
    /** @dev The PCT (protocol controlled treasury) address */
    address public pct;
    /** @dev Mapping from pegged token to deposit fee with 18 decimals. */
    mapping (address => uint256) public depositTransactionFees;
    /** @dev Mapping from pegged token to withdrawal fee with 18 decimals. */
    mapping (address => uint256) public withdrawalTransactionFees;
    /** @dev Mapping from pegged token address to total deposit supported. */
    mapping(address => uint256) public collateralCap;
    /** @dev Mapping from pegged token address to accrued fee amount. */
    mapping(address => uint256) public accruedFees;
    /** @dev Mapping from fxToken to peg token address to whether the peg is set. */
    mapping(address => mapping(address => bool)) public isFxTokenPegged;
    /** @dev Mapping from fxToken to peg token to deposit amount. */
    mapping(address => mapping(address => uint256)) public collateralDeposits;
    /** @dev Whether deposits are paused. */
    bool public areDepositsPaused;

    event SetPauseDeposits(bool isPaused);

    event SetDepositTransactionFee(address indexed token, uint256 fee);

    event SetWithdrawalTransactionFee(address indexed token, uint256 fee);
    
    event SetMaximumTokenDeposit(address indexed token, uint256 amount);

    event SetPct(address indexed pct);
    
    event TransferFundsPct(
        address indexed pct,
        address indexed token,
        uint256 amount
    );

    event SetFxTokenPeg(
        address indexed fxToken,
        address indexed peggedToken,
        bool isPegged
    );

    event Deposit(
        address indexed fxToken,
        address indexed peggedToken,
        address indexed account,
        uint256 amountIn,
        uint256 amountOut
    );
 
    event Withdraw(
        address indexed fxToken,
        address indexed peggedToken,
        address indexed account,
        uint256 amountIn,
        uint256 amountOut
    );

    modifier onlyPct() {
        require(msg.sender == pct, "PSM: Unauthorised: not pct");
        _;
    }

    constructor() {
        self = address(this);
    }

    /**
     * @dev Transfers out the accrued token fees to the owner.
     * @param collateralToken The peg collateral token to collect fees for.
     */
    function collectAccruedFees(address collateralToken) external onlyOwner {
        uint256 amount = accruedFees[collateralToken];
        require(amount > 0, "PSM: no fee accrual");
        accruedFees[collateralToken] -= amount;
        ERC20(collateralToken).transfer(msg.sender, amount);
    }

    /**
     * @dev Sets the deposit transaction fee for a token.
     * @param token The token to set the deposit transaction fee for.
     * @param fee The deposit transaction fee, where 1 ether = 100%.
     */
    function setDepositTransactionFee(
        address token,
        uint256 fee
    ) external onlyOwner {
        require(fee < 1 ether, "PSM: fee must be < 100%");
        depositTransactionFees[token] = fee;
        emit SetDepositTransactionFee(token, fee);
    }

    /**
     * @dev Sets the withdrawal transaction fee for a token.
     * @param token The token to set the withdrawal transaction fee for.
     * @param fee The withdrawal transaction fee, where 1 ether = 100%.
     */
    function setWithdrawalTransactionFee(
        address token,
        uint256 fee
    ) external onlyOwner {
        require(fee < 1 ether, "PSM: fee must be < 100%");
        withdrawalTransactionFees[token] = fee;
        emit SetWithdrawalTransactionFee(token, fee);
    }

    /**
     * @dev Sets whether deposits are paused.
     * @param isPaused Whether deposits are to be paused.
     */
    function setPausedDeposits(bool isPaused) external onlyOwner {
        areDepositsPaused = isPaused;
        emit SetPauseDeposits(isPaused);
    }

    /**
     * @dev Configures a fxToken peg to a collateral token.
     * @param fxTokenAddress The fxToken address to create the peg for.
     * @param peggedTokenAddress The peg collateral token address.
     * @param isPegged Whether the peg is being set.
     */
    function setFxTokenPeg(
        address fxTokenAddress,
        address peggedTokenAddress,
        bool isPegged
    ) external onlyOwner {
        fxToken _fxToken = fxToken(fxTokenAddress);
        assert(isFxTokenPegged[fxTokenAddress][peggedTokenAddress] != isPegged);
        bytes32 operatorRole = _fxToken.OPERATOR_ROLE();
        require(
            !isPegged || _fxToken.hasRole(operatorRole, self),
            "PSM: not an fxToken operator"
        );
        isFxTokenPegged[fxTokenAddress][peggedTokenAddress] = isPegged;
        if (!isPegged)
            _fxToken.renounceRole(operatorRole, self);
        emit SetFxTokenPeg(fxTokenAddress, peggedTokenAddress, isPegged);
    }

    /**
     * @dev Sets the maximum total deposit for a pegged token.
     * @param peggedToken The peg collateral token to set the collateral cap for.
     * @param capWithPeggedTokenDecimals The cap amount with the token decimals.
     */
    function setCollateralCap(
        address peggedToken,
        uint256 capWithPeggedTokenDecimals
    ) external onlyOwner {
        collateralCap[peggedToken] = capWithPeggedTokenDecimals;
        emit SetMaximumTokenDeposit(peggedToken, capWithPeggedTokenDecimals);
    }

    /** @dev Sets the PCT address.
     *       May disable PCT deposits by setting to address(0).
     * @param pctAddress The address of the new PCT.
     */
    function setPct(address pctAddress) external onlyOwner {
        pct = pctAddress;
        emit SetPct(pctAddress);
    }

    /**
     * @dev Receives a pegged token in exchange for minting fxToken for an account.
     * @param fxTokenAddress The fxToken address to be exchanged for the collateral token.
     * @param peggedTokenAddress The peg collateral token to be deposited.
     * @param amount The peg collateral token amount to be deposited.
     */
    function deposit(
        address fxTokenAddress,
        address peggedTokenAddress,
        uint256 amount
    ) external {
        require(!areDepositsPaused, "PSM: deposits are paused");
        require(
            isFxTokenPegged[fxTokenAddress][peggedTokenAddress],
            "PSM: fxToken not pegged to peggedToken"
        );
        require(
            amount > 0,
            "PSM: amount must be > 0"
        );
        ERC20 peggedToken = ERC20(peggedTokenAddress);
        require(
            collateralCap[peggedTokenAddress] == 0 ||
                amount + peggedToken.balanceOf(self)
                    <= collateralCap[peggedTokenAddress],
            "PSM: collateral cap exceeded"
        );
        peggedToken.safeTransferFrom(
            msg.sender,
            self,
            amount
        );
        // The fxToken amount (18 decimals) inclusive of fees.
        uint256 amountOutGross = calculateAmountForDecimalChange(
            peggedTokenAddress,
            fxTokenAddress,
            amount
        );
        // The fxToken amount (18 decimals) to be sent to the user. 
        uint256 amountOutNet = calculateAmountAfterFees(
            peggedTokenAddress,
            amountOutGross,
            true
        );
        require(amountOutNet > 0, "PSM: prevented nil transfer");
        // The input deposit amount exclusive of fees.
        uint256 amountInNet = calculateAmountAfterFees(
            peggedTokenAddress,
            amount,
            true
        );
        updateFeeForCollateral(
            peggedTokenAddress,
            amount,
            amountInNet
        );
        // Increase collateral/pegged token (input) amount from deposits.
        // The net amount is used here as the fee is not a deposit.
        collateralDeposits[fxTokenAddress][peggedTokenAddress] += amountInNet;
        fxToken(fxTokenAddress).mint(msg.sender, amountOutNet);
        emit Deposit(
            fxTokenAddress,
            peggedTokenAddress,
            msg.sender,
            amount,
            amountOutNet
        );
    }

    /**
     * @dev Burns an account's fxToken balance in exchange for a pegged token.
     * @param fxTokenAddress The fxToken address to exchange for a collateral token.
     * @param peggedTokenAddress The peg collateral token to exchange to.
     * @param amount The fxToken amount to be withdrawn.
     */
    function withdraw(
        address fxTokenAddress,
        address peggedTokenAddress,
        uint256 amount
    ) external {
        require(
            isFxTokenPegged[fxTokenAddress][peggedTokenAddress],
            "PSM: fxToken not pegged to peggedToken"
        );
        ERC20 peggedToken = ERC20(peggedTokenAddress);
        // The collateral amount out inclusive of fees. 
        uint256 amountOutGross = calculateAmountForDecimalChange(
            fxTokenAddress,
            peggedTokenAddress,
            amount
        );
        // While deposits are paused:
        //  - users can still withdraw all the pegged token liquidity currently in the contract
        //  - once the pegged token liquidity runs out, users can no longer call withdraw
        bool hasLiquidity = (
            collateralDeposits[fxTokenAddress][peggedTokenAddress]
                >= amountOutGross
        );
        require(
            !areDepositsPaused || hasLiquidity,
            "PSM: paused + no liquidity"
        );
        require(
            hasLiquidity,
            "PSM: contract lacks liquidity"
        );
        fxToken fxToken = fxToken(fxTokenAddress);
        require(
            fxToken.balanceOf(msg.sender) >= amount,
            "PSM: insufficient fx balance"
        );
        fxToken.burn(msg.sender, amount);
        // The collateral amount to be sent to the user, exclusive of fees.
        uint256 amountOutNet = calculateAmountAfterFees(
            peggedTokenAddress,
            amountOutGross,
            false
        );
        require(amountOutNet > 0, "PSM: prevented nil transfer");
        updateFeeForCollateral(
            peggedTokenAddress,
            amountOutGross,
            amountOutNet
        );
        // Reduce fxToken (amount out, gross) amount from deposits.
        // The gross amount is used here because fee is charged on
        // the pegged (collateral) token, not on the fxToken.
        // i.e. fees are charged after the withdrawal, not before.
        collateralDeposits[fxTokenAddress][peggedTokenAddress] -= amountOutGross;
        peggedToken.safeTransfer(msg.sender, amountOutNet);
        emit Withdraw(
            fxTokenAddress,
            peggedTokenAddress,
            msg.sender,
            amount,
            amountOutNet
        );
    }

    /**
     * @dev Allows the configured PCT contract to request ERC20 funds held by
     *      this PSM contract to be invested in external protocols.
     *      May also be used for upgrading the contract by moving liquidity
     *      into a new deployment.
     *      Only net funds (i.e. exclusive of accrued fees) may be moved out
     *      with this function.
     * @param token The token requested.
     * @param amount The amount to be transferred.
     */
    function requestFundsPct(address token, uint256 amount) external onlyPct {
        ERC20 erc20 = ERC20(token);
        uint256 balance = erc20.balanceOf(self);
        uint256 netBalance = balance - accruedFees[token];
        require(amount <= netBalance, "PSM: Lacks net balance");
        address pctAddress = pct;
        erc20.safeTransfer(pctAddress, amount);
        emit TransferFundsPct(
            pctAddress,
            token,
            amount
        );
    }

    /**
     * @dev Converts an input amount to after fees.
     * @param token The token to fetch the fee for.
     * @param amount The gross amount, before fees.
     * @param isDeposit whether the transaction is a deposit.
     */
    function calculateAmountAfterFees(
        address token,
        uint256 amount,
        bool isDeposit
    ) private returns (uint256) {
        uint256 transactionFee = isDeposit
            ? depositTransactionFees[token]
            : withdrawalTransactionFees[token];
        return amount * (1 ether - transactionFee) / 1 ether;
    }

    /**
     * @dev Updates the storage value for `accruedFees` for a collateral token.
     * @param collateralToken The token to update the fee for.
     * @param amountGross The gross transfer amount.
     * @param amountNet The net transfer amount.
     */
    function updateFeeForCollateral(
        address collateralToken,
        uint256 amountGross,
        uint256 amountNet
    ) private {
        if (amountNet == amountGross) return;
        assert(amountNet < amountGross);
        accruedFees[collateralToken] += amountGross - amountNet;
    }

    /**
     * @dev Converts an amount to match a different decimal count.
     * @param tokenIn The reference source token with same decimals as `amountIn`.
     * @param tokenOut The reference target token with decimals of returned value.
     * @param amountIn The amount, with decimals of `tokenIn`, to be transformed.
     */
    function calculateAmountForDecimalChange(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256) {
        uint256 decimalsIn = uint256(ERC20(tokenIn).decimals());
        uint256 decimalsOut = uint256(ERC20(tokenOut).decimals());
        if (decimalsIn == decimalsOut) return amountIn;
        uint256 decimalsDiff;
        if (decimalsIn > decimalsOut) {
            decimalsDiff = decimalsIn - decimalsOut;
            return amountIn / (10 ** decimalsDiff);
        }
        decimalsDiff = decimalsOut - decimalsIn;
        return amountIn * (10 ** decimalsDiff);
    }
}

