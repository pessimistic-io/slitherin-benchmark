// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20Upgradeable, SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {MathUpgradeable} from "./MathUpgradeable.sol";

import {IPSM, IERC20Override} from "./IPSM.sol";
import {ISmartVault} from "./ISmartVault.sol";
import {IStarToken} from "./IStarToken.sol";

//   /$$$$$$            /$$                                           /$$$$$$$$ /$$
//  /$$__  $$          | $$                                          | $$_____/|__/
// | $$  \__/  /$$$$$$ | $$$$$$$   /$$$$$$   /$$$$$$   /$$$$$$       | $$       /$$ /$$$$$$$   /$$$$$$  /$$$$$$$   /$$$$$$$  /$$$$$$
// |  $$$$$$  /$$__  $$| $$__  $$ /$$__  $$ /$$__  $$ /$$__  $$      | $$$$$   | $$| $$__  $$ |____  $$| $$__  $$ /$$_____/ /$$__  $$
//  \____  $$| $$  \ $$| $$  \ $$| $$$$$$$$| $$  \__/| $$$$$$$$      | $$__/   | $$| $$  \ $$  /$$$$$$$| $$  \ $$| $$      | $$$$$$$$
//  /$$  \ $$| $$  | $$| $$  | $$| $$_____/| $$      | $$_____/      | $$      | $$| $$  | $$ /$$__  $$| $$  | $$| $$      | $$_____/
// |  $$$$$$/| $$$$$$$/| $$  | $$|  $$$$$$$| $$      |  $$$$$$$      | $$      | $$| $$  | $$|  $$$$$$$| $$  | $$|  $$$$$$$|  $$$$$$$
//  \______/ | $$____/ |__/  |__/ \_______/|__/       \_______/      |__/      |__/|__/  |__/ \_______/|__/  |__/ \_______/ \_______/
//           | $$
//           | $$
//           |__/

/**
 * @notice PSM is a contract meant for swapping Stable Coin for STAR after taking a small fee. It will deposit
 * the Stable Coin it receives into some Smart Vault contract, such as depositing in Aave to get aStable Coin, to compound
 * the amount of Stable Coin that it has available to swap back to STAR, if STAR ever drifts under peg. The smart vault
 * contract will hold the Stable Coin or some derivative of Stable Coin, and it will be retrievable if necessary. When transitioning
 * to a new smart vault, the old smart vault will have its privileges revoked and the new smart vault will be executed.
 *
 * Using the PSM to swap Stable Coin to mint STAR will be profitable if STAR is over peg. It will be profitable to redeem STAR for Stable Coin
 * in the case that STAR is trading below $1. The PSM is intended to be used before redemptions happen in the main protocol.
 *
 * There will be a max on the PSM and a controller/owner which can update parameters such as max STAR minted,
 * smart vault used, fee, etc. The owner will be upgraded to a timelocked contract after a certain launch period.
 *
 */

contract PSM is ReentrancyGuardUpgradeable, OwnableUpgradeable, IPSM {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// ===========================================
    /// State variables, events, and initializer
    /// ===========================================

    uint256 internal constant MAX_UINT = type(uint).max;

    IERC20Upgradeable public stable;
    IStarToken public star;

    /// Conversion between Stable Coin and STAR, since Stable Coin is 6 decimals, and STAR is 18.
    uint256 public DECIMAL_CONVERSION;

    /// Receives fees from mint/redeem and from harvesting
    address public feeRecipient;

    /// SmartVault that deposits the Stable Coin to earn additional yield or put it to use.
    ISmartVault public smartVault;

    /// Max amount of STAR this contract can hold as debt
    /// To pause minting, set debt limit to 0.
    uint256 public starDebtLimit;

    /// Whether or not redeeming STAR is paused
    bool public redeemPaused;

    /// Current STAR Debt this contract holds
    uint256 public starContractDebt;

    /// Fee for each swap of STAR and Stable Coin, through mintSTAR or redeemSTAR functions. In basis points (out of 10000).
    uint256 public swapFee;

    /// 1 - swapFee, so the amount of STAR or Stable Coin you get in return for swapping.
    uint256 public swapFeeCompliment;

    /// basis points
    uint256 private constant SWAP_FEE_DENOMINATOR = 10000;

    uint256 private constant MAX_SWAP_FEE = 500;

    event STARMinted(uint256 starAmount, address minter, address recipient);

    event STARRedeemed(uint256 starAmount, address burner, address recipient);

    event STARContractDebtChanged(uint256 newstarContractDebt);

    event STARHarvested(uint256 starAmount);

    event NewFeeSet(uint256 _newSwapFee);

    event NewDebtLimitSet(uint256 _newDebtLimit);

    event RedeemPauseToggle(bool _paused);

    event NewFeeRecipientSet(address _newFeeRecipient);

    event NewSmartVaultSet(address _newVault);

    /**
     * @notice initializer function, sets all relevant parameters.
     */
    function initialize(
        address _stable,
        address _star,
        address _vault,
        address _feeRecipient,
        uint256 _limit,
        uint256 _swapFee
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(_stable != address(0), "!stable");
        stable = IERC20Upgradeable(_stable);

        DECIMAL_CONVERSION = 10 ** (18 - IERC20Override(_stable).decimals());

        require(_star != address(0), "!star");
        star = IStarToken(_star);

        require(_vault != address(0), "!smartVault");
        smartVault = ISmartVault(_vault);
        emit NewSmartVaultSet(_vault);

        require(_feeRecipient != address(0), "!feeRecipient");
        feeRecipient = _feeRecipient;
        emit NewFeeRecipientSet(_feeRecipient);

        starDebtLimit = _limit;
        emit NewDebtLimitSet(_limit);

        require(_swapFee <= MAX_SWAP_FEE, ">MAX_SWAP_FEE");
        swapFee = _swapFee;
        swapFeeCompliment = SWAP_FEE_DENOMINATOR - _swapFee;
        emit NewFeeSet(_swapFee);

        emit RedeemPauseToggle(false);
    }

    /// ===========================================
    /// External use functions
    /// ===========================================

    /**
     * @notice Send Stable Coin to receive STAR in return, at a 1 to 1 ratio minus the fee. Will increase debt of the contract by
     * that amount, if possible (lower than cap). Deposits into the smart vault.
     * @param _stableAmount The amount of Stable Coin the user would like to mint STAR with. Will be in terms of 10**6 decimals
     * @param _recipient Intended recipient for STAR minted
     * @return starAmount The amount of STAR the recipient receives back after the fee. Will be in terms of 10**18 decimals
     */
    function mintSTAR(
        uint256 _stableAmount,
        address _recipient
    ) external override nonReentrant returns (uint256 starAmount) {
        require(_stableAmount > 0, "0 mint not allowed");

        // Pull in Stable Coin from user
        stable.safeTransferFrom(msg.sender, address(this), _stableAmount);

        // Amount of STAR that will be minted, and amount of Stable Coin actually given to this contract
        uint256 stableAmountToDeposit = (_stableAmount * swapFeeCompliment) /
            SWAP_FEE_DENOMINATOR;
        starAmount = stableAmountToDeposit * DECIMAL_CONVERSION;
        uint256 newDebtAmount = starAmount + starContractDebt;
        require(
            newDebtAmount <= starDebtLimit,
            "Cannot mint more than PSM Debt limit"
        );

        // Send fee to recipient, in Stable Coin
        uint256 stableFeeAmount = _stableAmount - stableAmountToDeposit;

        stable.safeTransfer(feeRecipient, stableFeeAmount);

        // Deposit into smart vault
        _depositToVault(stableAmountToDeposit);

        // Mint recipient STAR
        star.mintFromWhitelistedContract(starAmount);
        IERC20Upgradeable(address(star)).safeTransfer(_recipient, starAmount);

        // Update contract debt
        starContractDebt = newDebtAmount;

        emit STARMinted(starAmount, msg.sender, _recipient);
        emit STARContractDebtChanged(newDebtAmount);
    }

    /**
     * @notice Send STAR to receive Stable Coin in return, at a 1 to 1 ratio minus the fee. Will decrease debt of the contract by
     * that amount, if possible (if less than 0 then just reduce to 0). Burns the STAR.
     * Receives the correct amount of Stable Coin from the Smart Vault when it is redeemed.
     * @param _starAmount The amount of STAR the user would like to redeem for stable. Will be in terms of 10**18 decimals
     * @param _recipient Intended recipient for Stable Coin returned
     * @return stableAmount The amount of Stable Coin the recipient receives back after the fee. Will be in terms of 10**6 decimals
     */
    function redeemSTAR(
        uint256 _starAmount,
        address _recipient
    ) external override nonReentrant returns (uint256 stableAmount) {
        require(!redeemPaused, "Redeem paused");
        require(_starAmount > 0, "0 redeem not allowed");

        // Pull in STAR from user

        IERC20Upgradeable(address(star)).safeTransferFrom(
            msg.sender,
            address(this),
            _starAmount
        );

        // Amount of Stable Coin that will be returned, and amount of STAR burned
        // Amount of STAR burned
        uint256 starBurned = (_starAmount * swapFeeCompliment) /
            SWAP_FEE_DENOMINATOR;
        stableAmount = starBurned / DECIMAL_CONVERSION;
        require(
            starBurned <= starContractDebt,
            "Burning more than the contract has in debt"
        );

        // Burn the STAR
        star.burnFromWhitelistedContract(starBurned);

        // Send fee to recipient, in STAR
        uint256 starFeeAmount = _starAmount - starBurned;

        IERC20Upgradeable(address(star)).safeTransfer(
            feeRecipient,
            starFeeAmount
        );

        // Withdraw from smart vault

        _withdrawFromVault(_recipient, stableAmount);

        // Update contract debt
        starContractDebt = starContractDebt - starBurned;

        _depositToVault(stable.balanceOf(address(this)));

        emit STARRedeemed(starBurned, msg.sender, _recipient);
        emit STARContractDebtChanged(starContractDebt);
    }

    function _depositToVault(uint256 stableAmount) internal {
        if (stableAmount != 0) {
            stable.safeApprove(address(smartVault), 0);
            stable.safeApprove(address(smartVault), stableAmount);
            smartVault.depositAndInvest(stableAmount);
        }
    }

    function _withdrawFromVault(
        address recipient,
        uint256 stableAmount
    ) internal {
        uint256 _share = smartVault.previewWithdraw(stableAmount);

        smartVault.withdraw(_share);

        stableAmount = MathUpgradeable.min(
            stableAmount,
            stable.balanceOf(address(this))
        );

        // Send back Stable Coin
        stable.safeTransfer(recipient, stableAmount);
    }

    /// ===========================================
    /// Admin parameter functions
    /// ===========================================

    /**
     * @notice Sets new swap fee
     */
    function setFee(uint256 _newSwapFee) external override onlyOwner {
        require(_newSwapFee <= MAX_SWAP_FEE, ">MAX_SWAP_FEE");
        swapFee = _newSwapFee;
        swapFeeCompliment = SWAP_FEE_DENOMINATOR - _newSwapFee;
        emit NewFeeSet(_newSwapFee);
    }

    /**
     * @notice Sets new STAR Debt limit
     *  Can be set to 0 to stop any new minting
     */
    function setDebtLimit(uint256 _newDebtLimit) external override onlyOwner {
        starDebtLimit = _newDebtLimit;
        emit NewDebtLimitSet(_newDebtLimit);
    }

    /**
     * @notice Sets whether redeeming is allowed or not
     */
    function toggleRedeemPaused(bool _paused) external override onlyOwner {
        redeemPaused = _paused;
        emit RedeemPauseToggle(_paused);
    }

    /**
     * @notice Sets fee recipient which will get a certain swapFee per swap
     */
    function setFeeRecipient(
        address _newFeeRecipient
    ) external override onlyOwner {
        require(_newFeeRecipient != address(0), "!feeRecipient");
        feeRecipient = _newFeeRecipient;
        emit NewFeeRecipientSet(_newFeeRecipient);
    }

    /**
     * @notice Sets new smart vault for Stable Coin utilization
     */
    function setSmartVault(address _newVault) external override onlyOwner {
        // Withdraw from old smart vault
        uint256 _shareBalance = smartVault.totalSupply();
        if (_shareBalance != 0) {
            smartVault.withdraw(_shareBalance);
        }
        stable.safeApprove(address(smartVault), 0);

        // Deposit into new vault after approving Stable Coin
        smartVault = ISmartVault(_newVault);

        uint256 _balance = stable.balanceOf(address(this));

        if (_balance != 0) {
            stable.safeApprove(_newVault, 0);
            stable.safeApprove(_newVault, _balance);
            smartVault.depositAndInvest(_balance);
        }

        emit NewSmartVaultSet(_newVault);
    }
}

