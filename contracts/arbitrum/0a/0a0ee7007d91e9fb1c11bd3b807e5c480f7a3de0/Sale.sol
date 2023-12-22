// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./Errors.sol";

/**
 * @dev Contract to perform sales and vestings of the token.
 * Allows users to buy token for other tokens or coins based on predefined rates.
 * Rates differs between plans. Some plans might not have rates at all.
 * These are predefined plans for vestings made before sale actually starts.
 * With time, owner is able to expand contract with new plans with different rates
 */

abstract contract Sale is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @dev All prices are multiplied by this number to allow smaller fractions of the currency pricing
     */
    uint256 constant PRICE_DIVIDER = 10_000;

    /**
     * @dev Decimals that native ETH has
     */
    uint256 constant ETH_DECIMALS = 18;

    /**
     * @dev The struct defining a single sale plan with rates for all tokens it can be sold with.
     *
     * @param cap Hard cap for the sale plan
     * @param startTime When the private sale round starts
     * @param endTime When the private sale round ends
     */
    struct SalePlan {
        uint256 cap;
        uint256 startTime;
        uint256 endTime;
    }

    /**
     * @dev The currency rate struct for defining rates in bulk
     *
     * @param token Token address this rate relates to or 0 if it relates to natural blockchain coin.
     * @param rate Rate for the token with 18 decimal places. Rate calculated as token_sold_amount = token_amount * rate / (10**18) with all decimal places
     */
    struct CurrencyRate {
        address token; // Token address used for the buy
        uint256 rate; // Rate for the exchange on purchase
    }

    /**
     * @dev Configuration struct defining whitelisted address with its cap
     */
    struct WhitelistConfiguration {
        address whitelisted;
        uint256 cap;
    }

    /**
     * @dev Struct sent on sale plan creation to configure rates and vestings for the plan accordingly
     */
    struct SalePlanConfiguration {
        SalePlan salePlan;
        CurrencyRate[] rates;
        WhitelistConfiguration[] whitelist;
    }

    /**
     * @dev The struct defining a single deposit made upon purchase or as a reward
     *
     * @param time Timestamp of the deposit - calculated as the round closing date
     * @param amount Amount of token vested with the deposit
     * @param withdrawn Amount already withdrawn from the deposit
     */
    struct Deposit {
        uint256 time;
        uint256 amount;
        uint256 withdrawn;
    }

    /**
     * @dev The event emitted on single sale made by the investor
     *
     * @param investor Address of the investor the deposit is linked to
     * @param plan The plan the deposit was made in
     * @param amount Amount that has been vested for the investor
     * @param transactionToken Token address the sale was made with
     */
    event Sold(address indexed investor, uint256 indexed plan, uint256 amount, address transactionToken);

    /**
     * @dev The event emitted when native currency is sent to the contract independently
     */
    event EthReceived(address indexed from, uint256 value);

    /**
     * @dev The event emitted contract is running sale
     *
     * @param onSale Flag if sale is running or not
     */
    event SetOnSale(bool onSale);

    /**
     * @dev The event emitted on new sale plan added to the list
     *
     * @param index Index of the new plan
     * @param isPublic Is newly created plan public to all users
     */
    event NewSalePlan(uint256 indexed index, bool isPublic);

    /**
     * @dev The event emitted on updated whitelist for the sale plan
     *
     * @param salePlan Index of the plan whitelist is being updated for
     */
    event WhitelistUpdated(uint256 indexed salePlan);

    /**
     * The address of the vault receiving all funds from the sales (tokens and coins)
     */
    address payable immutable vault;

    /**
     * The mapping of all deposits made in the sale contract
     */
    mapping(uint256 => mapping(address => Deposit)) public deposits;

    /**
     * The mapping of all currency rates for all sale plans
     */
    mapping(uint256 => mapping(address => uint256)) public currencyRates;

    /**
     * The mapping of all whitelisted addresses with caps
     */
    mapping(uint256 => mapping(address => uint256)) public whitelisted;

    /**
     * An array of whitelisted accounts
     */
    mapping(uint256 => address[]) public whitelistedAccounts;

    /**
     * A mapping of suspended accounts
     */
    mapping(address => bool) public suspended;

    /**
     * A mapping if given sale plan is public
     */
    mapping(uint256 => bool) public isPublic;

    /**
     * An array of all sale plans
     */
    SalePlan[] public salePlans;

    /**
     * The flag if sale contract is currently allowing third parties to perform any deposits
     */
    bool public onSale;

    /**
     * Mapping of total tokens sold in the plan
     */
    mapping(uint256 => uint256) public sold;

    /**
     * Modifier checking if contract is allowed to sell any tokens
     */
    modifier isOnSale(uint256 plan_) {
        if (plan_ >= salePlans.length) revert NotExists();
        if (!onSale || salePlans[plan_].startTime > block.timestamp) revert Blocked();
        if (salePlans[plan_].endTime <= block.timestamp) revert Timeout();
        _;
    }

    /**
     * Modifier checking if account isn't suspended
     */
    modifier notSuspended() {
        if (suspended[_msgSender()]) revert Suspended();
        _;
    }

    /**
     * @dev The constructor of the contract
     *
     * @param owner_ Owner address for the contract
     * @param vault_ The vault all funds from sales will be passed to
     * @param salePlans_ All plans preconfigured with contract creation
     */
    constructor(address owner_, address payable vault_, SalePlanConfiguration[] memory salePlans_) Ownable(owner_) {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;

        // Set vesting plans configurations
        for (uint256 i = 0; i < salePlans_.length;) {
            salePlans.push(salePlans_[i].salePlan);

            for (uint256 y = 0; y < salePlans_[i].rates.length;) {
                currencyRates[i][salePlans_[i].rates[y].token] = salePlans_[i].rates[y].rate;
                unchecked {
                    ++y;
                }
            }
            for (uint256 z = 0; z < salePlans_[i].whitelist.length;) {
                whitelisted[i][salePlans_[i].whitelist[z].whitelisted] = salePlans_[i].whitelist[z].cap;
                whitelistedAccounts[i].push(salePlans_[i].whitelist[z].whitelisted);
                unchecked {
                    ++z;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (salePlans_.length > 0) {
            onSale = true;
        }
    }

    /**
     * @dev Automatic retrieval of ETH funds
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @dev Return all plans (round) configurations
     */
    function getAllPlans() external view returns (SalePlan[] memory) {
        return salePlans;
    }

    /**
     * @dev Allowing the owner to start and stop the sale
     *
     * @param onSale_ Flag if sale should be started or stopped
     */
    function setOnSaleStatus(bool onSale_) external onlyOwner {
        if (onSale_ == onSale) revert AlreadySet();
        onSale = onSale_;

        emit SetOnSale(onSale);
    }

    /**
     * @dev Adds new sale plan to the list.
     *
     * @param salePlan_ New sale plan to add
     * @param public_ Is new plan added public
     */
    function addNewSalePlan(SalePlanConfiguration calldata salePlan_, bool public_) public onlyOwner {
        uint256 index = salePlans.length;
        salePlans.push(salePlan_.salePlan);

        for (uint256 i = 0; i < salePlan_.rates.length;) {
            currencyRates[index][salePlan_.rates[i].token] = salePlan_.rates[i].rate;
            unchecked {
                ++i;
            }
        }
        for (uint256 z = 0; z < salePlan_.whitelist.length;) {
            whitelisted[index][salePlan_.whitelist[z].whitelisted] = salePlan_.whitelist[z].cap;
            whitelistedAccounts[index].push(salePlan_.whitelist[z].whitelisted);
            unchecked {
                ++z;
            }
        }

        if (public_) {
            isPublic[index] = public_;
        }

        emit NewSalePlan(index, public_);
    }

    /**
     * @dev Locking or unlocking accounts from sales and withdrawals.
     *
     * @param account_ Account to be suspended or unlocked
     * @param locked_ If account should be locked or unlocked
     */
    function suspendAccount(address account_, bool locked_) external onlyOwner {
        suspended[account_] = locked_;
    }

    /**
     * @dev Updates whitelisted users for given sale plan
     *
     * @param salePlan_ The sale plan id whitelist is being updated for
     * @param whitelistedAddresses_ The whitelisted addresses caps are being updated for
     * @param caps_ Caps for whitelisted addresses
     */
    function addWhitelisted(uint256 salePlan_, address[] memory whitelistedAddresses_, uint256[] memory caps_)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < whitelistedAddresses_.length;) {
            if (whitelisted[salePlan_][whitelistedAddresses_[i]] > 0) {
                whitelistedAccounts[salePlan_].push(whitelistedAddresses_[i]);
            }
            whitelisted[salePlan_][whitelistedAddresses_[i]] = caps_[i];
            unchecked {
                ++i;
            }
        }
        emit WhitelistUpdated(salePlan_);
    }

    /**
     * @dev Method to perform the sale by making deposit in other token
     *
     * @param plan_ The plan the deposit is made to
     * @param amount_ Amount of token offered
     * @param token_ Token address the purchase is made with. 0 - if native currency is used.
     */
    function _deposit(uint256 plan_, uint256 amount_, address token_)
        internal
        isOnSale(plan_)
        notSuspended
        returns (uint256)
    {
        uint256 reward = _reward(token_, amount_, plan_);
        if (reward > _availableForPurchase(plan_, _msgSender()) || reward > salePlans[plan_].cap) {
            revert CapExceeded();
        }
        salePlans[plan_].cap -= reward;
        sold[plan_] += reward;
        _internalDeposit(plan_, _msgSender(), reward, salePlans[plan_].endTime);
        emit Sold(_msgSender(), plan_, amount_, token_);
        return reward;
    }

    /**
     * @dev Internal deposit method that is actually making the deposit record for given receiver
     *
     * @param salePlan_ Sale plan the deposit is being made in
     * @param receiver_ Receiver of the deposit
     * @param amount_ The amount of token vested
     * @param timestamp_ Time of the deposit
     */
    function _internalDeposit(uint256 salePlan_, address receiver_, uint256 amount_, uint256 timestamp_) internal {
        if (receiver_ == address(0)) revert ZeroAddress();
        if (amount_ == 0) revert ZeroValue();

        deposits[salePlan_][receiver_].amount += amount_;
        deposits[salePlan_][receiver_].time = timestamp_;
    }

    /**
     * @dev Method returning amount of tokens still available for purchase for given investora address.
     *
     * @param plan_ The plan the cap is calculated for
     * @param investor_ Investor address to check
     *
     * @return Available token amount investor can still purchase in current sale plan.
     */
    function _availableForPurchase(uint256 plan_, address investor_) internal view returns (uint256) {
        uint256 user_cap = whitelisted[plan_][investor_];

        if (isPublic[plan_]) {
            user_cap = salePlans[plan_].cap;
        } else {
            user_cap -= deposits[plan_][investor_].amount;
        }

        return user_cap;
    }

    /**
     * @dev Calculate amount of the reward to be sent to the user in return
     *
     * Note: This is an example function. Using saved rates as a single token price
     * Price is being normalized based on the tokens decimals used in the purchase
     * This assumes that all tokens used in the purchase are implementing decimals()
     * method.
     *
     * @param token_ The token address used to pay for the purchase
     * @param amount_ The amount of the token used for the purchase
     * @param plan_ The plan the sale is connected to
     *
     * @return The amount of token user should be rewarded with
     */
    function _reward(address token_, uint256 amount_, uint256 plan_) internal virtual returns (uint256) {
        uint256 tokenDecimals = ETH_DECIMALS; // In case token used for purchase is actually a native coin
        if (token_ != address(0)) {
            tokenDecimals = IERC20Metadata(token_).decimals();
        }

        // Depending on the difference in decimal places - we need to normalize amounts in opposite ways
        if (tokenDecimals > _decimals(plan_)) {
            uint256 decimalDiff = tokenDecimals - _decimals(plan_);
            return amount_ * _price(token_, plan_) / (10 ** decimalDiff) / PRICE_DIVIDER;
        } else {
            uint256 decimalDiff = _decimals(plan_) - tokenDecimals;
            return amount_ * _price(token_, plan_) * (10 ** decimalDiff) / PRICE_DIVIDER;
        }
    }

    /**
     * @dev Price rewarded for purchase in given plan with token.
     * The method used by _reward() to calculate the amount
     *
     * @param token_ The token address used for purchase
     * @param plan_ The plan id the purchase is being made in
     *
     * @return The price of a single item purchased in given currency (token)
     */
    function _price(address token_, uint256 plan_) internal virtual returns (uint256) {
        if (currencyRates[plan_][token_] == 0) revert WrongCurrency();
        return currencyRates[plan_][token_];
    }

    /**
     * @dev Decimal places of the item being sold in the sale
     *
     * Note: This method is used by example implementation that can be overriden
     * by any sale contract using this implementation
     *
     * @return The decimal places of sold item
     */
    function _decimals(uint256) internal virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev Internal funds retrieval and passing method to the vault
     *
     * @param investor_ Investor address making deposit
     * @param token_ The token address used to purchase the coin or 0 if its native coin of the platform
     * @param amount_ The amount of the purchase
     *
     */
    function _retrieveFunds(address investor_, address token_, uint256 amount_) internal {
        if (token_ == address(0)) {
            if (amount_ != msg.value) revert InsufficientFunds();
            // slither-disable-start low-level-calls
            // slither-disable-next-line arbitrary-send-eth
            (bool sent,) = vault.call{value: amount_}("");
            // slither-disable-end low-level-calls
            if (!sent) revert InsufficientFunds();
        } else {
            if (msg.value > 0) revert WrongCurrency();
            IERC20(token_).safeTransferFrom(investor_, vault, amount_);
        }
    }
}

