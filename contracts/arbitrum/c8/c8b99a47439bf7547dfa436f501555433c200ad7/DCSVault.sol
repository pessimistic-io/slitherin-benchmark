// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20, ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Math } from "./Math.sol";
import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { ICegaState } from "./ICegaState.sol";
import { DCSProduct } from "./DCSProduct.sol";
import { VaultStatus, Withdrawal } from "./Structs.sol";
import { DCSCalculations } from "./DCSCalculations.sol";

contract DCSVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event WithdrawalQueued(address indexed vaultAddress, address indexed receiver, uint256 amountShares);

    address public cegaStateAddress;
    ICegaState public cegaState;
    DCSProduct public dcsProduct;

    // Vault Set Up information
    address public immutable baseAssetAddress; // will usually be usdc
    address public immutable alternativeAssetAddress; // asset returned if final spot falls below strike
    string public oracleName; // maybe dont need this but keeping for now

    // Trade information
    uint256 public vaultStart;
    uint256 public tradeStartDate;
    uint256 public tradeEndDate;
    uint256 public aprBps;
    uint256 public tenorInDays;
    uint256 public initialBaseSpotPrice;
    uint256 public strikeBasePrice; // strike price set at beginning of trade, in units of baseAsset
    address public auctionWinner;

    Withdrawal[] public withdrawalQueue;

    // Vault Status Information
    VaultStatus public vaultStatus;
    uint256 public finalBaseSpotPrice; // final spot price at trade end, in units of baseAsset
    bool public isPayoffInBaseAsset; // whether we payoff in base asset or alternative asset
    uint256 public notionalInBaseAsset;
    uint256 public vaultFinalPayoff; // this unit will be base asset if isPayoffWithBaseAsset == true
    uint256 public totalYield;

    // Deposits & withdraw information
    uint256 public queuedWithdrawalsSharesAmount;
    uint256 public queuedWithdrawalsCount;

    /**
     * @notice Creates a new DCSVault that is owned by a DCSProduct
     * @param _baseAssetAddress is the address of the underlying asset
     * @param _alternativeAssetAddress is the address of the alternative asset
     * @param _tokenName is the name of the token
     * @param _tokenSymbol is the name of the token symbol
     */
    constructor(
        address _cegaStateAddress,
        address _baseAssetAddress,
        address _alternativeAssetAddress,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _vaultStart,
        string memory _oracleName
    ) ERC20(_tokenName, _tokenSymbol) {
        cegaStateAddress = _cegaStateAddress;
        cegaState = ICegaState(cegaStateAddress);
        baseAssetAddress = _baseAssetAddress;
        alternativeAssetAddress = _alternativeAssetAddress;
        isPayoffInBaseAsset = true;
        vaultStart = _vaultStart;
        oracleName = _oracleName;
        dcsProduct = DCSProduct(owner());
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @notice Asserts whether the sender has the DEFAULT_ADMIN_ROLE
     */
    modifier onlyDefaultAdmin() {
        require(cegaState.isDefaultAdmin(msg.sender), "403:DA");
        _;
    }

    /**
     * @notice Asserts whether the sender has the TRADER_ADMIN_ROLE
     */
    modifier onlyTraderAdmin() {
        require(cegaState.isTraderAdmin(msg.sender), "403:TA");
        _;
    }

    /**
     * @notice Asserts whether the sender has the OPERATOR_ADMIN_ROLE
     */
    modifier onlyOperatorAdmin() {
        require(cegaState.isOperatorAdmin(msg.sender), "403:OA");
        _;
    }

    /**
     * @notice Asserts that the vault has been initialized & is a Cega Vault
     */
    modifier onlyValidVault() {
        require(vaultStart != 0, "400:VA");
        _;
    }

    modifier onlyProductOrOperatorAdmin() {
        require(msg.sender == owner() || cegaState.isOperatorAdmin(msg.sender), "403:POA");
        _;
    }

    /**
     * @notice Returns base assets in vault
     */
    function totalBaseAssets() public view returns (uint256) {
        return IERC20(baseAssetAddress).balanceOf(address(this));
    }

    /**
     * @notice Returns alternative assets in vault
     */
    function totalAlternativeAssets() public view returns (uint256) {
        return IERC20(alternativeAssetAddress).balanceOf(address(this));
    }

    /**
     * @notice Converts units of shares to assets
     * @param shares is the number of vault tokens
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        if (isPayoffInBaseAsset) {
            return (shares * totalBaseAssets()) / _totalSupply;
        }
        return (shares * totalAlternativeAssets()) / _totalSupply;
    }

    /**
     * @notice Converts units assets to shares
     * @param assets is the amount of base assets
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        uint256 _totalBaseAssets = totalBaseAssets();
        if (_totalBaseAssets == 0 || _totalSupply == 0) return assets;
        return (assets * _totalSupply) / _totalBaseAssets;
    }

    /**
     * Product can deposit into the vault
     * @param assets is the number of underlying assets to be deposited
     * @param receiver is the address of the original depositor
     */
    function deposit(uint256 assets, address receiver) public onlyOwner returns (uint256) {
        uint256 shares = convertToShares(assets);

        _mint(receiver, shares);

        return shares;
    }

    /**
     * Redeem a given amount of shares in return for assets
     * Shares are burned from the caller
     * @param shares is the amount of shares (vault tokens) to be redeemed
     */
    function redeem(uint256 shares) external onlyOwner returns (uint256) {
        uint256 assets = convertToAssets(shares);

        _burn(msg.sender, shares);

        return assets;
    }

    // TRADING METHODS
    // TODO - create NFT / token to send to a winning MM?

    /**
     * Trader admin has ability to set the vault to "DepositsOpen" state
     */
    function openVaultDeposits() public onlyTraderAdmin {
        require(vaultStatus == VaultStatus.DepositsClosed, "500:WS");
        vaultStatus = VaultStatus.DepositsOpen;
    }

    /**
     * @notice Trader admin sets the trade data after the auction. This Starts the trade
     */
    function startTrade(
        uint256 _tradeStartDate,
        uint256 _tradeEndDate,
        uint256 _aprBps,
        uint256 _tenorInDays,
        uint256 _strikeBasePrice,
        uint256 _initialSpotBasePrice,
        address _auctionWinner
    ) public onlyTraderAdmin onlyValidVault {
        require(vaultStatus == VaultStatus.NotTraded, "500:WS");
        require(_tradeStartDate >= vaultStart, "400:TD");
        require(_tradeEndDate > _tradeStartDate, "400:TE");

        // allow for a 1 day difference in input tenor and derived tenor
        uint256 derivedDays = (_tradeEndDate - _tradeStartDate) / 1 days;
        if (derivedDays < _tenorInDays) {
            require(_tenorInDays - derivedDays <= 1, "400:TN");
        } else {
            require(derivedDays - _tenorInDays <= 1, "400:TN");
        }

        tradeStartDate = _tradeStartDate;
        tradeEndDate = _tradeEndDate;
        aprBps = _aprBps;
        tenorInDays = _tenorInDays;
        strikeBasePrice = _strikeBasePrice;
        initialBaseSpotPrice = _initialSpotBasePrice;
        auctionWinner = _auctionWinner;
        notionalInBaseAsset = totalBaseAssets();
    }

    // SETTLEMENT METHODS
    /**
     * @notice Calculates the final payoff for a given vault.
     * IF isPayoffInBaseAsset = false, we shift left by 10 ** 18 to avoid precision.
     * The UI MUST SHIFT THIS BACK TO GET THE ACTUAL AMOUNT OF TOKENS FOR THE ALTERNATIVE ASSET
     */
    function calculateVaultFinalPayoff() public onlyValidVault returns (uint256) {
        require((vaultStatus == VaultStatus.TradeExpired || vaultStatus == VaultStatus.PayoffCalculated), "500:WS");
        finalBaseSpotPrice = DCSCalculations.getSpotPriceAtExpiry(oracleName, tradeEndDate, cegaStateAddress);
        // convert to alternative asset
        if (finalBaseSpotPrice < strikeBasePrice) {
            isPayoffInBaseAsset = false;
            uint256 notionalInAlternativeAsset = DCSCalculations.convertBaseAssetToAlternativeAsset(
                notionalInBaseAsset,
                strikeBasePrice
            );
            uint256 couponInAlternativeAsset = DCSCalculations.calculateCouponPayment(
                notionalInAlternativeAsset,
                aprBps,
                tradeStartDate,
                tenorInDays
            );
            totalYield = couponInAlternativeAsset;
            vaultFinalPayoff = notionalInAlternativeAsset + couponInAlternativeAsset;
        } else {
            uint256 couponInBaseAsset = DCSCalculations.calculateCouponPayment(
                notionalInBaseAsset,
                aprBps,
                tradeStartDate,
                tenorInDays
            );
            totalYield = couponInBaseAsset;
            vaultFinalPayoff = notionalInBaseAsset + couponInBaseAsset;
        }

        vaultStatus = VaultStatus.PayoffCalculated;
        return vaultFinalPayoff;
    }

    // MM does settlement with us in alternative asset
    // we burn their nft? check valid position?
    function settlementInAlternativeAsset() public nonReentrant {
        // Payoff in alternative asset
        require(!isPayoffInBaseAsset, "not paying off in alternative");
        // Only auction winner can call this function
        require(msg.sender == auctionWinner, "not the auction winner");
        // require counter party to have enough funds
        require(IERC20(alternativeAssetAddress).balanceOf(msg.sender) >= vaultFinalPayoff);

        // we send USDC notional
        IERC20(baseAssetAddress).approve(address(this), notionalInBaseAsset);
        IERC20(baseAssetAddress).safeTransfer(msg.sender, notionalInBaseAsset);

        // take correct amount in alternative asset from them
        IERC20(alternativeAssetAddress).safeTransferFrom(msg.sender, address(this), vaultFinalPayoff);
    }

    /**
     * @notice Transfers the correct amount of fees to the fee recipient
     */
    function collectFees() public nonReentrant onlyTraderAdmin onlyValidVault {
        require(vaultStatus == VaultStatus.PayoffCalculated, "500:WS");

        uint256 totalFees = DCSCalculations.calculateFees(vaultFinalPayoff, dcsProduct.getFeeBps());

        totalFees = Math.min(totalFees, vaultFinalPayoff);
        IERC20(baseAssetAddress).safeTransfer(cegaState.feeRecipient(), totalFees);

        vaultStatus = VaultStatus.FeesCollected;
    }

    /**
     * @notice Queues a withdrawal for the token holder of a specific vault token
     * @param amountShares is the number of vault tokens to be redeemed
     */
    function addToWithdrawalQueue(uint256 amountShares) public nonReentrant onlyValidVault {
        require(amountShares >= dcsProduct.minWithdrawalAmount(), "400:WA");

        IERC20(address(this)).safeTransferFrom(msg.sender, address(this), amountShares);
        withdrawalQueue.push(Withdrawal({ amountShares: amountShares, receiver: msg.sender }));
        queuedWithdrawalsCount += 1;
        queuedWithdrawalsSharesAmount += amountShares;
        emit WithdrawalQueued(address(this), msg.sender, amountShares);
    }

    /**
     * @notice Processes all the queued withdrawals in the withdrawal queue
     * @param maxProcessCount is the maximum number of withdrawals to process in the queue
     */
    function processWithdrawalQueue(uint256 maxProcessCount) public nonReentrant onlyTraderAdmin onlyValidVault {
        // Needs zombie state so that we can restore the vault
        require(vaultStatus == VaultStatus.FeesCollected || vaultStatus == VaultStatus.Zombie, "500:WS");

        uint256 processCount = Math.min(queuedWithdrawalsCount, maxProcessCount);
        uint256 amountAssets;
        Withdrawal memory withdrawal;
        while (processCount > 0) {
            withdrawal = withdrawalQueue[queuedWithdrawalsCount - 1];

            // redeem does the conversion in base / altnerative assets
            amountAssets = this.redeem(withdrawal.amountShares);
            if (isPayoffInBaseAsset) {
                IERC20(baseAssetAddress).safeTransfer(withdrawal.receiver, amountAssets);
            } else {
                IERC20(alternativeAssetAddress).safeTransfer(withdrawal.receiver, amountAssets);
            }

            withdrawalQueue.pop();
            queuedWithdrawalsCount -= 1;
            processCount -= 1;
        }

        if (queuedWithdrawalsCount == 0) {
            if (totalBaseAssets() == 0 && totalAlternativeAssets() == 0 && totalSupply() > 0) {
                vaultStatus = VaultStatus.Zombie;
            } else {
                vaultStatus = VaultStatus.WithdrawalQueueProcessed;
            }
        }
    }

    /**
     * @notice Resets the vault to the default state after the trade is settled
     */
    function rolloverVault() public onlyTraderAdmin onlyValidVault {
        require(vaultStatus == VaultStatus.WithdrawalQueueProcessed, "500:WS");
        require(tradeEndDate != 0, "400:TE");
        if (isPayoffInBaseAsset) {
            vaultStart = tradeEndDate;
            tradeStartDate = 0;
            tradeEndDate = 0;
            aprBps = 0;
            vaultStatus = VaultStatus.DepositsClosed;
            totalYield = 0;
            vaultFinalPayoff = 0;
            initialBaseSpotPrice = 0;
            strikeBasePrice = 0;
            auctionWinner = address(0);
        } else {
            vaultStatus = VaultStatus.Zombie;
        }
    }

    /**
     * @notice Calculates the current yield accumulated to the current day for a given vault
     */
    function calculateCurrentYield() public onlyValidVault returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime > tradeEndDate) {
            vaultStatus = VaultStatus.TradeExpired;
        }
        uint256 currentYield = DCSCalculations.calculateCouponPayment(
            notionalInBaseAsset,
            aprBps,
            tradeStartDate,
            tenorInDays
        );
        totalYield = currentYield;
    }

    /**
     * Operator admin has ability to override the vault's status
     * @param _vaultStatus is the new status for the vault
     */
    function setVaultStatus(VaultStatus _vaultStatus) public onlyProductOrOperatorAdmin onlyValidVault {
        vaultStatus = _vaultStatus;
    }

    /**
     * Default admin has an override to set the knock in status for a vault
     * @param newState is the new state for isKnockedIn
     */
    function setIsPayoffInBaseAsset(bool newState) public onlyDefaultAdmin onlyValidVault {
        isPayoffInBaseAsset = newState;
    }
}

