// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IHandle.sol";
import "./ITreasury.sol";
import "./IValidator.sol";
import "./IVaultLibrary.sol";
import "./IComptroller.sol";
import "./IOracle.sol";
import "./IInterest.sol";
import "./IfxToken.sol";
import "./Roles.sol";

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

/**
 * @dev Stores the main protocol data and configurations.
        Holds a reference to all protocol contracts.
 */
contract Handle is IHandle, Initializable, UUPSUpgradeable, IValidator, Roles {
    using SafeMath for uint256;

    /** @dev Configured collateral tokens.
             Not necessarily currently valid for deposit. */
    address[] private collateralTokens;
    /** @dev Configured collateral tokens that may be currently deposit. */
    mapping(address => bool) public override isCollateralValid;
    /** @dev Configured collateral data */
    mapping(address => CollateralData) private collateralDetails;
    /** @dev Total collateral balance held by the Treasury.
             mapping(token => collateral balance) */
    mapping(address => uint256) public totalBalances;

    /** @dev Configured and valid fxToken array */
    address[] private validFxTokens;
    /** @dev Valid fxToken mapping */
    mapping(address => bool) public override isFxTokenValid;

    /** @dev mapping(user => mapping(fxToken => vault data)) */
    mapping(address => mapping(address => Vault)) public vaults;

    /** @dev Ratio of maximum Treasury collateral that can be managed by
             the PCT at a given time. */
    uint256 public override pctCollateralUpperBound;
    // Per mille fee settings
    /** @dev Mint fee as a per mille value, or a percentage with 1 decimal. */
    uint256 public override mintFeePerMille;
    /** @dev Burn fee as a per mille value, or a percentage with 1 decimal. */
    uint256 public override burnFeePerMille;
    /** @dev Withdraw fee as a per mille value, or a percentage with 1 decimal. */
    uint256 public override withdrawFeePerMille;
    /** @dev Deposit fee as a per mille value, or a percentage with 1 decimal. */
    uint256 public override depositFeePerMille;

    /** @dev Address sending for protocol fees */
    address public override FeeRecipient;
    /** @dev Canonical Wrapped Ether address */
    address public override WETH;
    /** @dev mapping(token => oracle aggregator) */
    mapping(address => address) public oracles;

    /** @dev Whether all the relevant functions in all protocol contracts
             are currently paused (disabled) for security reasons. */
    bool public override isPaused;

    /** @dev Address for the Treasury contract */
    address payable public override treasury;
    /** @dev Address for the Comptroller contract */
    address public override comptroller;
    /** @dev Address for the VaultLibrary contract */
    address public override vaultLibrary;
    /** @dev Address for the FxKeeperPool contract */
    address public override fxKeeperPool;
    /** @dev Address for the PCT contract */
    address public override pct;
    /** @dev Address for the Liquidator contract */
    address public override liquidator;
    /** @dev Address for the Interest contract */
    address public override interest;
    /** @dev Address for the Referral contract */
    address public override referral;
    /** @dev Address for the Forex contract */
    address public override forex;
    /** @dev Address for the Rewards contract */
    address public override rewards;

    modifier notPaused() {
        require(!isPaused, "Paused");
        _;
    }

    /** @dev Proxy initialisation function */
    function initialize(address weth) public initializer {
        __AccessControl_init();
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        WETH = weth;
    }

    /** @dev Setter for pctCollateralUpperBound */
    function setCollateralUpperBoundPCT(uint256 ratio)
        external
        override
        onlyAdmin
    {
        pctCollateralUpperBound = ratio;
    }

    /** @dev Setter for isPaused */
    function setPaused(bool value) external override onlyAdmin {
        isPaused = value;
    }

    /** @dev Configure an ERC20 as a valid fxToken */
    function setFxToken(address token) public override onlyAdmin {
        require(token != address(0), "Invalid token address");
        if (isFxTokenValid[token] == true) return;
        validFxTokens.push(token);
        isFxTokenValid[token] = true;
        emit ConfigureFxToken(token, false);
    }

    /** @dev Invalidate an existing fxToken and remove it from the protocol */
    function removeFxToken(address token) external override onlyAdmin {
        uint256 tokenIndex = validFxTokens.length;
        for (uint256 i = 0; i < tokenIndex; i++) {
            if (validFxTokens[i] == token) {
                tokenIndex = i;
                break;
            }
        }
        // Assert that token was found.
        assert(tokenIndex < validFxTokens.length);
        delete isFxTokenValid[token];
        if (tokenIndex < validFxTokens.length - 1) {
            // Replace to-be-deleted item with last element and then pop array.
            validFxTokens[tokenIndex] = validFxTokens[validFxTokens.length - 1];
            validFxTokens.pop();
        } else {
            // Token index is last element, so no need to pop array.
            validFxTokens.pop();
        }
        emit ConfigureFxToken(token, true);
    }

    /** @dev Configure an ERC20 as a valid collateral token */
    function setCollateralToken(
        address token,
        uint256 mintCR,
        uint256 liquidationFee,
        uint256 interestRatePerMille
    ) external override onlyOperatorOrAdmin {
        require(mintCR >= 110, "CR");
        CollateralData storage collateral = collateralDetails[token];
        // Only push new collateral token if it does not exist.
        if (collateral.mintCR == 0) collateralTokens.push(token);
        // Re-enable collateral as valid if 1st time or if it was removed.
        if (!isCollateralValid[token]) isCollateralValid[token] = true;
        // Charge interest to write R value for current interest rate.
        IInterest(interest).charge();
        collateral.mintCR = mintCR;
        collateral.liquidationFee = liquidationFee;
        collateral.interestRate = interestRatePerMille;
        emit ConfigureCollateralToken(token);
    }

    /** @dev Invalidate an existing collateral token for new deposits.
             The token will still be valid for existing deposits. */
    function removeCollateralToken(address token) external override onlyAdmin {
        // Cannot remove a token, as this would orphan user collateral. Mark it invalid instead.
        delete isCollateralValid[token];
        emit ConfigureCollateralToken(token);
    }

    /**
     * @dev Update all Handle contract components
     * @param components an array with the address of the components, where:
              index 0: treasury
              index 1: comptroller
              index 2: vaultLibrary
              index 3: fxKeeperPool
              index 4: pct
              index 5: liquidator
              index 6: interest
              index 7: referral
              index 8: forex
              index 9: rewards
     */
    function setComponents(address[] memory components)
        external
        override
        onlyAdmin
    {
        uint256 l = components.length;
        for (uint256 i = 0; i < l; i++) {
            require(components[i] != address(0), "Invalid address");
        }
        treasury = payable(components[0]);
        comptroller = components[1];
        vaultLibrary = components[2];
        fxKeeperPool = components[3];
        pct = components[4];
        liquidator = components[5];
        interest = components[6];
        referral = components[7];
        forex = components[8];
        rewards = components[9];
        for (uint256 i = 0; i < 9; i++) {
            /*
             * Grant operator roles if needed.
             * Skip:
             * - VaultLibrary
             * - fxKeeperPool
             * - referral
             * - forex
             * - rewards (i never reaches 9).
             */
            if (i == 2 || i == 3 || i == 8) continue;
            // Role is only granted if not yet assigned.
            grantRole(OPERATOR_ROLE, components[i]);
        }
    }

    /** @dev Getter for collateralTokens */
    function getAllCollateralTypes()
        public
        view
        override
        returns (address[] memory collateral)
    {
        collateral = collateralTokens;
    }

    /** @dev Getter for collateralDetails */
    function getCollateralDetails(address collateral)
        external
        view
        override
        returns (CollateralData memory)
    {
        return collateralDetails[collateral];
    }

    /**
     * @dev Updates a vault's debt position.
            Can only be called by the comptroller
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @param increase Whether to increase or decrease the position
     */
    function updateDebtPosition(
        address account,
        uint256 amount,
        address fxToken,
        bool increase
    ) external override onlyOperator notPaused {
        // Charge interest.
        IInterest(interest).charge();
        // Compound debt by getting current principal + interest.
        uint256 debt = getDebt(account, fxToken);
        uint256 interest =
            IVaultLibrary(vaultLibrary).calculateInterest(account, fxToken);
        // Mint interest fxTokens for fee recipient.
        if (interest > 0) IfxToken(fxToken).mint(FeeRecipient, interest);
        // Reset R0 value.
        resetVaultR0(account, fxToken);
        // Increase/decrease vault debt.
        vaults[account][fxToken].debt = increase
            ? debt.add(amount)
            : debt.sub(amount);
        emit UpdateDebt(account, fxToken);
    }

    /**
     * @dev Updates a vault's collateral balance.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @param collateralToken The vault collateral token
     * @param increase Whether to increase or decrease the balance
     */
    function updateCollateralBalance(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken,
        bool increase
    ) external override onlyOperator notPaused {
        uint256 currentAccountBalance =
            vaults[account][fxToken].collateralBalance[collateralToken];

        vaults[account][fxToken].collateralBalance[collateralToken] = increase
            ? currentAccountBalance.add(amount)
            : currentAccountBalance.sub(amount);

        totalBalances[collateralToken] = increase
            ? totalBalances[collateralToken].add(amount)
            : totalBalances[collateralToken].sub(amount);

        emit UpdateCollateral(account, fxToken, collateralToken);
    }

    /** @dev Setter for FeeRecipient */
    function setFeeRecipient(address feeRecipient)
        external
        override
        onlyAdmin
        validAddress(feeRecipient)
    {
        FeeRecipient = feeRecipient;
    }

    /** @dev Setter for all protocol transaction fees */
    function setFees(
        uint256 _withdrawFeePerMille,
        uint256 _depositFeePerMille,
        uint256 _mintFeePerMille,
        uint256 _burnFeePerMille
    ) external override onlyAdmin {
        withdrawFeePerMille = _withdrawFeePerMille;
        depositFeePerMille = _depositFeePerMille;
        burnFeePerMille = _burnFeePerMille;
        mintFeePerMille = _mintFeePerMille;
    }

    /**
     * @dev Getter for an user's collateral balance for a given collateral type
     * @param account The user's address
     * @param fxToken The vault to check
     * @param collateralType The collateral token address
     * @return balance
     */
    function getCollateralBalance(
        address account,
        address collateralType,
        address fxToken
    ) external view override returns (uint256 balance) {
        balance = vaults[account][fxToken].collateralBalance[collateralType];
    }

    /**
     * @dev Getter for all collateral types deposited into a vault.
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return collateral Each collateral type deposited
     * @return balances Balance for each collateral type deposited
     */
    function getBalance(address account, address fxToken)
        external
        view
        override
        returns (address[] memory collateral, uint256[] memory balances)
    {
        collateral = getAllCollateralTypes();
        uint256 j = collateral.length;
        uint256[] memory _balances = new uint256[](j);
        for (uint256 i = 0; i < j; i++) {
            _balances[i] = vaults[account][fxToken].collateralBalance[
                collateral[i]
            ];
        }
        balances = _balances;
    }

    /**
     * @dev Getter for a vault's interest collateral R0 value
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @param collateral The collateral token for the R0 value
     * @return R0 The R0 interest value
     */
    function getCollateralR0(
        address account,
        address fxToken,
        address collateral
    ) external view override returns (uint256 R0) {
        R0 = vaults[account][fxToken].R0[collateral];
    }

    /**
     * @dev Sets the R0 values of a vault to the current R values for the vault
            so that interest starts being accrued from this point in time.
     * @param account The vault account
     * @param fxToken The vault fxToken
     */
    function resetVaultR0(address account, address fxToken) private {
        (uint256[] memory R, address[] memory collateralTokens) =
            IInterest(interest).getCurrentR();
        uint256 j = collateralTokens.length;
        Vault storage vault = vaults[account][fxToken];
        for (uint256 i = 0; i < j; i++) {
            vault.R0[collateralTokens[i]] = R[i];
        }
    }

    /**
     * @dev Getter for a vault's debt including interest
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return debt The amount of fxToken debt outstanding including interest
     */
    function getDebt(address account, address fxToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 debt = vaults[account][fxToken].debt;
        return
            debt.add(
                IVaultLibrary(vaultLibrary).calculateInterest(account, fxToken)
            );
    }

    /**
     * @dev Getter for a vault's debt excluding interest
     * @param account The vault account
     * @param fxToken The vault fxToken
     * @return debt the amount of fxToken debt outstanding excluding interest
     */
    function getPrincipalDebt(address account, address fxToken)
        external
        view
        override
        returns (uint256)
    {
        return vaults[account][fxToken].debt;
    }

    /**
     * @dev Getter for a token unit price in ETH
     * @param token The token to get the price of
     * @return quote The price of 1 token in ETH
     */
    function getTokenPrice(address token)
        public
        view
        override
        returns (uint256 quote)
    {
        if (token == WETH) return 1 ether;
        require(oracles[token] != address(0), "No oracle for token");
        quote = IOracle(oracles[token]).getRate(token);
        require(quote > 0, "Token price is zero");
    }

    /**
     * @dev Sets an oracle for a given token
     * @param token The token to set the oracle for
     * @param oracle The oracle to use for the token
     */
    function setOracle(address token, address oracle)
        external
        override
        onlyAdmin
    {
        require(token != address(0) && oracle != address(0), "IZ");
        oracles[token] = oracle;
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

