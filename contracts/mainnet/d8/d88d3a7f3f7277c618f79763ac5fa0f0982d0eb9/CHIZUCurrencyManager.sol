/*


            .':looooc;.    .,cccc,.    'cccc:. 'ccccc:. .:ccccccccccccc:. .:ccc:.    .;cccc,        
          .lOXNWWWNWNNKx;. .kWNNWk.    lNWNWK, dWWWNWX; :XWNWNNNNNWNWWWX: :XWNWX:    .OWNNWd.       
         ;0NNNNNXKXNNNNNXd..kWNNWk.    lNNNWK, oNNNNWK; :KWNNNNNNNNNNNN0, :XWNWX:    .OWNNNd.       
        ;0WNNN0c,.';x0Oxoc..kWNNW0c;:::xNNNWK, oNNNNWK; .;;;;:dKNNNNNXd'  :XWNWX:    .OWNNNd.       
       .oNNNWK;     ...    .kWNNNNNNNNNNNNNWK, :0NWNXx'     .l0NNNNNk;.   :XWNWX:    .OWNNNd.       
       .oNNNWK;     ...    .kWNNNNNWWWWNNNNWK,  .,c:'.    .;ONNNNN0c.     :XWNWXc    'OWNNNd.       
        ;0NNNN0l,.':xKOkdc..kWNNW0occcckNNNWK, .:oddo,.  'xXNNNNNKo::::;. '0WNNN0c,,:xXNNWXc        
         ;0NNNNNXKXNNNNNXo..kWNNWk.    lNNNWK,.oNNNNWK; :KNNNNNNNNNNNNNXc  :KNNNNNNXNNNNNNd.        
          .lkXNWNNWWNNKx;. .kWNNWk.    lNWNWK, :KNWNNk' oNWNNWNNNNNWNNWNc   ,dKNWWNNWWNXk:.         
            .':looolc;.    .,c::c,.    ':::c;.  .:c:,.  ':c::c:::c::::c:.     .;coodol:'.           


*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AddressUpgradeable.sol";

import "./IERC20.sol";
import "./IRoles.sol";
import "./Constants.sol";
import "./console.sol";

error CHIZUCurrencyManager_Core_Should_Be_Contract();

error CHIZUCurrencyManager_Currency_Not_Allowed();
error CHIZUCurrencyManager_Address_Not_Allowed();

error CHIZUCurrencyManager_Cannot_Deposit_To_Address_Zero();
error CHIZUCurrencyManager_Cannot_Deposit_To_Contract();
error CHIZUCurrencyManager_Cannot_Deposit_Zero_Amount();
error CHIZUCurrencyManager_Not_Approved();

error CHIZUCurrencyManager_Cannot_Withdraw_From_Address_Zero();
error CHIZUCurrencyManager_Cannot_Withdraw_From_Contract();
error CHIZUCurrencyManager_Cannot_Withdraw_Zero_Amount();

error CHIZUCurrencyManager_Insufficient_Allowance(uint256 amount);
error CHIZUCurrencyManager_Insufficient_Available_Funds(uint256 amount);

contract CHIZUCurrencyManager {
    using AddressUpgradeable for address payable;

    /// @dev Address of initialized core
    IRoles internal chizuCore;

    /// @dev List of coins registered in the current manager
    mapping(address => bool) public currencyWhitelist;

    /// @dev The balance that the account has for each current
    mapping(address => mapping(address => uint256))
        private currencyToAccountToBalance;

    // @dev The total balance  for each current
    mapping(address => uint256) private currencyTotal;

    /**
     * @param currency The currency that has become the whitelist
     * @param available whether the currency is available
     */
    event CurrencyWhitelistChanged(address indexed currency, bool available);

    /**
     * @param currency the currency to be transfered
     * @param from The address of sender
     * @param to The address of recevier
     * @param amount The amount to transfer
     */
    event CurrencyTransfered(
        address indexed currency,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /**
     * @param currency the currency to be withdrawn
     * @param from The address to withdraw
     * @param to The address of recevier
     * @param amount The amount to transfer
     */
    event CurrencyWithdrawn(
        address indexed currency,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /**
     * @param currency the currency to be deposited
     * @param from The address to deposit
     * @param to The address of recevier
     * @param amount The amount to transfer
     */
    event CurrencyDeposited(
        address indexed currency,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    modifier onlyAdmin() {
        if (!chizuCore.isAdmin(msg.sender)) {
            revert CHIZUCurrencyManager_Address_Not_Allowed();
        }
        _;
    }

    modifier onlyChizu() {
        if (!chizuCore.isModule(msg.sender) && !chizuCore.isAdmin(msg.sender)) {
            revert CHIZUCurrencyManager_Address_Not_Allowed();
        }
        _;
    }

    /**
     * @notice Defines requirements for the collection factory at deployment time.
     * @param _chizuCore The address of the contract defining roles for collections to use.
     */
    constructor(address _chizuCore) {
        chizuCore = IRoles(_chizuCore);
        currencyWhitelist[CURRENCY_ETH] = true;
    }

    /// @dev Fallback function that runs when nothing is called
    receive() external payable {
        depositETHFor(msg.sender);
    }

    /**
     * @dev Only admin is available
     * @param _chizuCore The address of the core to update
     */
    function updateCore(address _chizuCore) external onlyAdmin {
        chizuCore = IRoles(_chizuCore);
    }

    /**
     * @notice  Method to deposit ethereum for msg.sender
     */
    function depositETH() public payable {
        depositETHFor(msg.sender);
    }

    /**
     * @notice Method to deposit ethereum for specific account
     * @param account The account to deposit
     */
    function depositETHFor(address account) public payable {
        if (msg.value == 0) {
            revert CHIZUCurrencyManager_Cannot_Deposit_Zero_Amount();
        }
        if (account == address(0)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Address_Zero();
        }
        if (account == address(this)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Contract();
        }
        currencyToAccountToBalance[CURRENCY_ETH][account] += msg.value;
        currencyTotal[CURRENCY_ETH] += msg.value;
        emit CurrencyDeposited(CURRENCY_ETH, msg.sender, account, msg.value);
    }

    /**
     * @notice Method to deposit erc20 for msg.sender
     * @param currency The address of currency to deposit
     * @param amount The amount to deposit
     */
    function depositERC20(address currency, uint256 amount) external {
        depositERC20For(currency, msg.sender, amount);
    }

    /**
     * @notice Method to deposit erc20 for specific account
     * @param currency The address of currency to deposit
     * @param account The account to deposit
     * @param amount The amount to deposit
     */
    function depositERC20For(
        address currency,
        address account,
        uint256 amount
    ) public {
        if (!currencyWhitelist[currency]) {
            revert CHIZUCurrencyManager_Currency_Not_Allowed();
        }
        if (amount == 0) {
            revert CHIZUCurrencyManager_Cannot_Deposit_Zero_Amount();
        }
        if (account == address(0)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Address_Zero();
        }
        if (account == address(this)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Contract();
        }

        uint256 accountBalance = currencyToAccountToBalance[currency][account];
        IERC20 token = IERC20(currency);
        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < (amount + accountBalance)) {
            revert CHIZUCurrencyManager_Insufficient_Allowance(
                amount + accountBalance
            );
        }
        currencyToAccountToBalance[currency][account] += amount;
        currencyTotal[currency] += amount;

        token.transferFrom(msg.sender, address(this), amount);

        emit CurrencyDeposited(currency, msg.sender, account, amount);
    }

    /**
     * @notice  Method to withdraw ethereum to msg.sender
     * @param amount The amount of withdraw
     */
    function withdrawETH(uint256 amount) public {
        uint256 accountBalance = currencyToAccountToBalance[CURRENCY_ETH][
            msg.sender
        ];
        if (amount == 0) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_Zero_Amount();
        }
        if (accountBalance < amount) {
            revert CHIZUCurrencyManager_Insufficient_Available_Funds(
                accountBalance
            );
        }
        if (msg.sender == address(0)) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_From_Address_Zero();
        }
        if (msg.sender == address(this)) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_From_Contract();
        }

        currencyToAccountToBalance[CURRENCY_ETH][msg.sender] -= amount;
        currencyTotal[CURRENCY_ETH] -= amount;

        payable(msg.sender).transfer(amount);

        emit CurrencyWithdrawn(CURRENCY_ETH, msg.sender, msg.sender, amount);
    }

    /**
     * @notice  Method to withdraw erc20 to msg.sender
     * @param amount The amount of withdraw
     */
    function withdrawERC20(address currency, uint256 amount) public {
        if (!currencyWhitelist[currency]) {
            revert CHIZUCurrencyManager_Currency_Not_Allowed();
        }
        if (amount == 0) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_Zero_Amount();
        }
        if (msg.sender == address(0)) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_From_Address_Zero();
        }
        if (msg.sender == address(this)) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_From_Contract();
        }

        uint256 accountBalance = currencyToAccountToBalance[currency][
            msg.sender
        ];
        if (accountBalance < amount) {
            revert CHIZUCurrencyManager_Insufficient_Available_Funds(
                accountBalance
            );
        }
        currencyToAccountToBalance[currency][msg.sender] -= amount;
        currencyTotal[currency] -= amount;

        IERC20 token = IERC20(currency);
        token.transfer(msg.sender, amount);

        emit CurrencyWithdrawn(currency, msg.sender, msg.sender, amount);
    }

    /**
     * @dev Only chizu is available
     * @dev Use it to implement protocol fee
     * @param currency The currency to reduce
     * @param from The account to reduce currency
     * @param amount The amount to reduce
     */
    function chizuReduceCurrencyFrom(
        address currency,
        address from,
        uint256 amount
    ) external onlyChizu {
        if (!currencyWhitelist[currency]) {
            revert CHIZUCurrencyManager_Currency_Not_Allowed();
        }
        uint256 accountBalance = currencyToAccountToBalance[currency][from];
        if (accountBalance < amount) {
            revert CHIZUCurrencyManager_Insufficient_Available_Funds(
                accountBalance
            );
        }

        currencyToAccountToBalance[currency][from] -= amount;
        currencyTotal[currency] -= amount;

        emit CurrencyWithdrawn(currency, from, address(this), amount);
    }

    /**
     * @dev Only chizu is available
     * @dev Use it to implement owner fee / order fulfill
     * @param currency The currency to transfer
     * @param from The account to send
     * @param to The account to receive
     * @param amount The amount to transfer
     */
    function chizuTransferCurrencyFrom(
        address currency,
        address from,
        address to,
        uint256 amount
    ) external onlyChizu {
        if (!currencyWhitelist[currency]) {
            revert CHIZUCurrencyManager_Currency_Not_Allowed();
        }
        if (amount == 0) {
            revert CHIZUCurrencyManager_Cannot_Withdraw_Zero_Amount();
        }
        if (to == address(0)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Address_Zero();
        }
        if (to == address(this)) {
            revert CHIZUCurrencyManager_Cannot_Deposit_To_Contract();
        }

        uint256 accountBalance = currencyToAccountToBalance[currency][from];
        if (accountBalance < amount) {
            revert CHIZUCurrencyManager_Insufficient_Available_Funds(
                accountBalance
            );
        }
        currencyToAccountToBalance[currency][from] -= amount;
        currencyToAccountToBalance[currency][to] += amount;

        emit CurrencyTransfered(currency, from, to, amount);
    }

    /**
     * @notice Functions that withdraw the available ether
     * @notice Only admin is available
     */
    function adminWithdrawAvailableETH() external onlyAdmin {
        uint256 totalBalance = currencyTotal[CURRENCY_ETH];
        uint256 realTotalBalance = address(this).balance;
        require(
            realTotalBalance > totalBalance,
            "CHIZUCurrencyManager : Not enough balance"
        );

        uint256 availableBalance = realTotalBalance - totalBalance;

        payable(msg.sender).transfer(availableBalance);

        emit CurrencyWithdrawn(
            CURRENCY_ETH,
            address(this),
            msg.sender,
            availableBalance
        );
    }

    /**
     * @notice Functions that withdraw the available erc20
     * @notice Only admin is available
     */
    function adminWithdrawAvailableERC20(address currency) external onlyAdmin {
        require(
            currencyWhitelist[currency],
            "CHIZUCurrencyManager : Currency Not Allowed"
        );
        IERC20 token = IERC20(currency);
        uint256 totalBalance = currencyTotal[currency];
        uint256 realTotalBalance = token.balanceOf(address(this));
        require(
            realTotalBalance > totalBalance,
            "CHIZUCurrencyManager : Not enough balance"
        );

        uint256 availableBalance = realTotalBalance - totalBalance;

        token.transfer(msg.sender, availableBalance);

        emit CurrencyWithdrawn(
            currency,
            address(this),
            msg.sender,
            availableBalance
        );
    }

    /**
     * @notice The function to change the whitelist
     * @param currency The currency to be changed
     * @param isAvailable Whether the currency is available
     */
    function adminChangeCurrencyWhitelist(address currency, bool isAvailable)
        external
        onlyAdmin
    {
        currencyWhitelist[currency] = isAvailable;
        emit CurrencyWhitelistChanged(currency, isAvailable);
    }

    /**
     * @notice Function to know the balance held by the account for each current
     * @return balance The balance of currency for account
     */
    function balanceOf(address currency, address account)
        public
        view
        returns (uint256)
    {
        return currencyToAccountToBalance[currency][account];
    }

    /**
     * @param currency the currency that is suppported
     * @return isSupported Whether the currency is availalbe
     */
    function isSupportedCurrency(address currency)
        external
        view
        returns (bool)
    {
        return currencyWhitelist[currency];
    }

    /**
     * @return Available ETH currently available
     */
    function availableETH() external view returns (uint256) {
        return address(this).balance - currencyTotal[CURRENCY_ETH];
    }

    /**
     * @param currency The currency to know
     * @return Available ERC20 currently available
     */
    function availableERC20(address currency) external view returns (uint256) {
        IERC20 token = IERC20(currency);
        return token.balanceOf(address(this)) - currencyTotal[currency];
    }
}

