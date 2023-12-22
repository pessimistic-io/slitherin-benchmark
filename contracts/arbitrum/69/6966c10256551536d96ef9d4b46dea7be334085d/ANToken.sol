// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AccessControl.sol";
import "./EnumerableSet.sol";
import "./PRBMathUD60x18.sol";

import "./IANToken.sol";
import "./IWormholeRelayer.sol";
import "./IWormholeReceiver.sol";

contract ANToken is IANToken, IWormholeReceiver, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathUD60x18 for uint256;

    uint256 public constant MAXIMUM_SUPPLY = 100_000_000_000 ether;
    uint256 public constant MAXIMUM_GAS_LIMIT = 250_000;
    uint256 public constant MINIMUM_GAS_LIMIT = 100_000;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant MAXIMUM_BURN_PERCENTAGE = 400;
    uint256 public constant MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION = 400;
    bytes32 public constant LIQUIDITY_PROVIDER_ROLE = keccak256("LIQUIDITY_PROVIDER_ROLE");

    IWormholeRelayer public immutable wormholeRelayer;
    address public commissionRecipient;
    uint256 public gasLimit = MAXIMUM_GAS_LIMIT;
    uint256 public purchaseProtectionPeriod = 1 minutes;
    uint256 public saleProtectionPeriod = 60 minutes;
    uint256 public maximumPurchaseAmountDuringProtectionPeriod = 15_000_000 ether;
    uint256 public percentageOfSalesCommission = 150;
    uint256 public cumulativeAdjustmentFactor = PRBMathUD60x18.fromUint(1);
    uint256 public tradingEnabledTimestamp;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    bool public isTradingEnabled;

    EnumerableSet.AddressSet private _liquidityPools;
    EnumerableSet.AddressSet private _whitelistedAccounts;
    EnumerableSet.AddressSet private _blocklistedAccounts;
    EnumerableSet.AddressSet private _commissionExemptAccounts;
    EnumerableSet.AddressSet private _sourceAddresses;
    EnumerableSet.AddressSet private _burnProtectedAccounts;

    mapping(address => bool) public isPurchaseMadeDuringProtectionPeriodByAccount;
    mapping(address => uint256) public availableAmountToPurchaseDuringProtectionPeriodByAccount;
    mapping(bytes32 => bool) public notUniqueHash;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @param wormholeRelayer_ Wormhole relayer contract address.
    /// @param commissionRecipient_ Commission recipient address.
    /// @param liquidityProvider_ Liquidity provider address.
    constructor(IWormholeRelayer wormholeRelayer_, address commissionRecipient_, address liquidityProvider_) {
        wormholeRelayer = wormholeRelayer_;
        commissionRecipient = commissionRecipient_;
        _name = "AN on Arbitrum";
        _symbol = "AN";
        _commissionExemptAccounts.add(commissionRecipient_);
        _burnProtectedAccounts.add(commissionRecipient_);
        _burnProtectedAccounts.add(address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIQUIDITY_PROVIDER_ROLE, liquidityProvider_);
    }

    /// @inheritdoc IANToken
    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_totalSupply != MAXIMUM_SUPPLY) {
            revert MaximumSupplyNotMinted();
        }
        if (_liquidityPools.length() == 0) {
            revert EmptySetOfLiquidityPools();
        }
        if (_whitelistedAccounts.length() == 0) {
            revert EmptySetOfWhitelistedAccounts();
        }
        if (isTradingEnabled) {
            revert TradingAlreadyEnabled();
        }
        isTradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }

    /// @inheritdoc IANToken
    function withdrawAccumulatedCommission() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 commissionAmount = _balances[address(this)];
        if (commissionAmount > 0) {
            _transfer(address(this), commissionRecipient, commissionAmount);
            emit AccumulatedCommissionWithdrawn(commissionAmount);
        }
    }

    /// @inheritdoc IANToken
    function nullifyBlocklistedAccount(address account_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (!_blocklistedAccounts.contains(account_)) {
            revert NotFoundInBlocklistedAccountsSet({account: account_});
        }
        uint256 amount = balanceOf(account_);
        _balances[account_] = 0;
        _balances[commissionRecipient] += amount;
        emit BlocklistedAccountNullified(account_, amount);
    }

    /// @inheritdoc IANToken
    function mint(address account_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (isTradingEnabled) {
            revert ForbiddenToMintTokens();
        }
        if (_totalSupply + amount_ > MAXIMUM_SUPPLY) {
            revert MaximumSupplyExceeded();
        }
        _totalSupply += amount_;
        unchecked {
            _balances[account_] += amount_;
        }
        emit Transfer(address(0), account_, amount_);
    }

    /// @inheritdoc IANToken
    function burn(uint256 percentage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isTradingEnabled) {
            revert ForbiddenToBurnTokens();
        }
        if (percentage_ > MAXIMUM_BURN_PERCENTAGE) {
            revert MaximumBurnPercentageExceeded();
        }
        uint256 currentTotalSupply = _totalSupply;
        uint256 nonBurnableSupply = _totalSupplyOfBurnProtectedAccounts();
        uint256 burnableSupply = currentTotalSupply - nonBurnableSupply;
        uint256 burnAmount = currentTotalSupply * percentage_ / BASE_PERCENTAGE;
        uint256 adjustmentFactor = burnableSupply.div(burnableSupply - burnAmount);
        cumulativeAdjustmentFactor = cumulativeAdjustmentFactor.mul(adjustmentFactor);
        _totalSupply = nonBurnableSupply + burnableSupply.div(adjustmentFactor);
        emit Transfer(address(0), address(0), currentTotalSupply - _totalSupply);
    }

    /// @inheritdoc IANToken
    function addLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.add(accounts_[i])) {
                revert AlreadyInLiquidityPoolsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit LiquidityPoolsAdded(accounts_);
    }

    /// @inheritdoc IANToken
    function removeLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.remove(accounts_[i])) {
                revert NotFoundInLiquidityPoolsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit LiquidityPoolsRemoved(accounts_);
    }

    /// @inheritdoc IANToken
    function addWhitelistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_whitelistedAccounts.add(accounts_[i])) {
                revert AlreadyInWhitelistedAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit WhitelistedAccountsAdded(accounts_);
    }

    /// @inheritdoc IANToken
    function removeWhitelistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_whitelistedAccounts.remove(accounts_[i])) {
                revert NotFoundInWhitelistedAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit WhitelistedAccountsRemoved(accounts_);
    }

    /// @inheritdoc IANToken
    function addBlocklistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_blocklistedAccounts.add(accounts_[i])) {
                revert AlreadyInBlocklistedAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit BlocklistedAccountsAdded(accounts_);
    }

    /// @inheritdoc IANToken
    function removeBlocklistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_blocklistedAccounts.remove(accounts_[i])) {
                revert NotFoundInBlocklistedAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit BlocklistedAccountsRemoved(accounts_);
    }

    /// @inheritdoc IANToken
    function addCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_commissionExemptAccounts.add(accounts_[i])) {
                revert AlreadyInCommissionExemptAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit CommissionExemptAccountsAdded(accounts_);
    }

    /// @inheritdoc IANToken
    function removeCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_commissionExemptAccounts.remove(accounts_[i])) {
                revert NotFoundInCommissionExemptAccountsSet({account: accounts_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit CommissionExemptAccountsRemoved(accounts_);
    }

    /// @inheritdoc IANToken
    function addSourceAddresses(address[] calldata sourceAddresses_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < sourceAddresses_.length; ) {
            if (!_sourceAddresses.add(sourceAddresses_[i])) {
                revert AlreadyInSourceAddressesSet({sourceAddress: sourceAddresses_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit SourceAddressesAdded(sourceAddresses_);
    }

    /// @inheritdoc IANToken
    function removeSourceAddresses(address[] calldata sourceAddresses_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < sourceAddresses_.length; ) {
            if (!_sourceAddresses.remove(sourceAddresses_[i])) {
                revert NotFoundInSourceAddressesSet({sourceAddress: sourceAddresses_[i]});
            }
            unchecked {
                i++;
            }
        }
        emit SourceAddressesRemoved(sourceAddresses_);
    }

    /// @inheritdoc IANToken
    function updateGasLimit(uint256 gasLimit_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (gasLimit < MINIMUM_GAS_LIMIT && gasLimit > MAXIMUM_GAS_LIMIT) {
            revert InvalidGasLimit();
        }
        gasLimit = gasLimit_;
        emit GasLimitUpdated(gasLimit_);
    }

    /// @inheritdoc IANToken
    function updatePurchaseProtectionPeriod(uint256 purchaseProtectionPeriod_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isTradingEnabled) {
            revert ForbiddenToUpdatePurchaseProtectionPeriod();
        }
        purchaseProtectionPeriod = purchaseProtectionPeriod_;
        emit PurchaseProtectionPeriodUpdated(purchaseProtectionPeriod_);
    }

    /// @inheritdoc IANToken
    function updateSaleProtectionPeriod(uint256 saleProtectionPeriod_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isTradingEnabled) {
            revert ForbiddenToUpdateSaleProtectionPeriod();
        }
        saleProtectionPeriod = saleProtectionPeriod_;
        emit SaleProtectionPeriodUpdated(saleProtectionPeriod_);
    }

    /// @inheritdoc IANToken
    function updateCommissionRecipient(address commissionRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address currentCommissionRecipient = commissionRecipient;
        if (currentCommissionRecipient == commissionRecipient_ || commissionRecipient_ == address(0)) {
            revert InvalidCommissionRecipient();
        }
        removeBurnProtectedAccount(currentCommissionRecipient);
        commissionRecipient = commissionRecipient_;
        addBurnProtectedAccount(commissionRecipient_);
        emit CommissionRecipientUpdated(commissionRecipient_);
    }

    /// @inheritdoc IANToken
    function updateMaximumPurchaseAmountDuringProtectionPeriod(
        uint256 maximumPurchaseAmountDuringProtectionPeriod_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (isTradingEnabled) {
            revert ForbiddenToUpdateMaximumPurchaseAmountDuringProtectionPeriod();
        }
        maximumPurchaseAmountDuringProtectionPeriod = maximumPurchaseAmountDuringProtectionPeriod_;
        emit MaximumPurchaseAmountDuringProtectionPeriodUpdated(maximumPurchaseAmountDuringProtectionPeriod_);
    }

    /// @inheritdoc IANToken
    function updatePercentageOfSalesCommission(
        uint256 percentageOfSalesCommission_
    )   
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (percentageOfSalesCommission_ > MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION) {
            revert MaximumPercentageOfSalesCommissionExceeded();
        }
        percentageOfSalesCommission = percentageOfSalesCommission_;
        emit PercentageOfSalesCommissionUpdated(percentageOfSalesCommission_);
    }

    /// @inheritdoc IERC20
    function approve(address spender_, uint256 amount_) external returns (bool) {
        if (msg.sender == address(0) || spender_ == address(0)) {
            revert ZeroAddressEntry();
        }
        _allowances[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    /// @inheritdoc IANToken
    function transferMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool) 
    {
        uint256 cost = quoteEVMDeliveryPrice(targetChain_);
        if (msg.value != cost) {
            revert InvalidMsgValue();
        }
        if (msg.sender == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (_blocklistedAccounts.contains(msg.sender) || _blocklistedAccounts.contains(to_)) {
            revert Blocklisted();
        }
        if (!isTradingEnabled) {
            if (_hasLimits(msg.sender, to_)) {
                revert ForbiddenToTransferTokens({
                    from: msg.sender,
                    to: to_,
                    amount: amount_
                });
            }
        }
        _burn(msg.sender, amount_);
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_,
            targetAddress_,
            abi.encode(msg.sender, to_, amount_),
            0,
            gasLimit
        );
        return true;
    }
    
    /// @inheritdoc IERC20
    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        _allowances[from_][msg.sender] -= amount_;
        _transfer(from_, to_, amount_);
        return true;
    }

    /// @inheritdoc IANToken
    function transferFromMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address from_,
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool) 
    {
        uint256 cost = quoteEVMDeliveryPrice(targetChain_);
        if (msg.value != cost) {
            revert InvalidMsgValue();
        }
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (_blocklistedAccounts.contains(from_) || _blocklistedAccounts.contains(to_)) {
            revert Blocklisted();
        }
        if (!isTradingEnabled) {
            if (_hasLimits(from_, to_)) {
                revert ForbiddenToTransferTokens({
                    from: from_,
                    to: to_,
                    amount: amount_
                });
            }
        }
        _allowances[from_][msg.sender] -= amount_;
        _burn(from_, amount_);
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_,
            targetAddress_,
            abi.encode(from_, to_, amount_),
            0,
            gasLimit
        );
        return true;
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload_,
        bytes[] memory,
        bytes32 sourceAddress_,
        uint16 sourceChain_,
        bytes32 deliveryHash_
    )
        external
        payable
    {
        if (msg.sender != address(wormholeRelayer)) {
            revert InvalidCallee();
        }
        if (notUniqueHash[deliveryHash_]) {
            revert NotUniqueHash();
        }
        if (!_sourceAddresses.contains(address(uint160(uint256(sourceAddress_))))) {
            revert InvalidSourceAddress();
        }
        (address from, address to, uint256 amount) = abi.decode(payload_, (address, address, uint256));
        _mint(to, amount);
        notUniqueHash[deliveryHash_] = true;
        emit TokensReceived(from, to, amount, sourceChain_);
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function allowance(address owner_, address spender_) external view returns (uint256) {
        return _allowances[owner_][spender_];
    }

    /// @inheritdoc IERC20Metadata
    function name() external view returns (string memory) {
        return _name;
    }
    
    /// @inheritdoc IERC20Metadata
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IANToken
    function isLiquidityPool(address account_) external view returns (bool) {
        return _liquidityPools.contains(account_);
    }

    /// @inheritdoc IANToken
    function isWhitelistedAccount(address account_) external view returns (bool) {
        return _whitelistedAccounts.contains(account_);
    }

    /// @inheritdoc IANToken
    function isBlocklistedAccount(address account_) external view returns (bool) {
        return _blocklistedAccounts.contains(account_);
    }

    /// @inheritdoc IANToken
    function isCommissionExemptAccount(address account_) external view returns (bool) {
        return _commissionExemptAccounts.contains(account_);
    }

    /// @inheritdoc IANToken
    function isBurnProtectedAccount(address account_) external view returns (bool) {
        return _burnProtectedAccounts.contains(account_);
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc IANToken
    function addBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.add(account_)) {
            revert AlreadyInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].div(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountAdded(account_);
    }

    /// @inheritdoc IANToken
    function removeBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.remove(account_)) {
            revert NotFoundInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].mul(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountRemoved(account_);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256) {
        if (_burnProtectedAccounts.contains(account_)) {
            return _balances[account_];
        } else {
            return _balances[account_].div(cumulativeAdjustmentFactor);
        }
    }

    /// @inheritdoc IANToken
    function quoteEVMDeliveryPrice(uint16 targetChain_) public view returns (uint256 cost_) {
        (cost_, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain_, 0, gasLimit);
    }

    /// @notice Moves `amount_` of tokens from `from_` to `to_`. 
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @param amount_ Amount of tokens to transfer.
    function _transfer(address from_, address to_, uint256 amount_) private {
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (_blocklistedAccounts.contains(from_) || _blocklistedAccounts.contains(to_)) {
            revert Blocklisted();
        }
        if (!isTradingEnabled) {
            if (_hasLimits(from_, to_)) {
                revert ForbiddenToTransferTokens({
                    from: from_,
                    to: to_,
                    amount: amount_
                });
            }
        } else {
            uint256 timeElapsed = block.timestamp - tradingEnabledTimestamp;
            if (timeElapsed < purchaseProtectionPeriod && _liquidityPools.contains(from_)) {
                if (_whitelistedAccounts.contains(tx.origin)) {
                    if (!isPurchaseMadeDuringProtectionPeriodByAccount[tx.origin]) {
                        availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] 
                            = maximumPurchaseAmountDuringProtectionPeriod - amount_;
                        isPurchaseMadeDuringProtectionPeriodByAccount[tx.origin] = true;
                    } else {
                        availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] -= amount_;
                    }
                } else {
                    revert ForbiddenToTransferTokens({
                        from: from_,
                        to: to_,
                        amount: amount_
                    });
                }
            }
            if (timeElapsed < saleProtectionPeriod && _liquidityPools.contains(to_)) {
                revert ForbiddenToSaleTokens();
            }
        }
        bool shouldTakeSalesCommission;
        if (!_commissionExemptAccounts.contains(from_) && _liquidityPools.contains(to_)) {
            shouldTakeSalesCommission = true;
        }
        uint256 adjustmentFactor = cumulativeAdjustmentFactor;
        uint256 adjustedAmount = amount_.mul(adjustmentFactor);
        uint256 amountToReceive = shouldTakeSalesCommission ? _takeSalesCommission(from_, amount_) : amount_;
        uint256 adjustedAmountToReceive = amountToReceive.mul(adjustmentFactor);
        if (!_burnProtectedAccounts.contains(from_) && _burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += amountToReceive;
        } else if (_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= amount_;
            _balances[to_] += adjustedAmountToReceive;
        } else if (!_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += adjustedAmountToReceive;
        } else {
            _balances[from_] -= amount_;
            _balances[to_] += amountToReceive;
        }
        emit Transfer(from_, to_, amountToReceive);
    }

    /// @notice Creates the `amount_` tokens and assigns them to an `account_`, increasing the total supply.
    /// @param account_ Account address.
    /// @param amount_ Amount of tokens to mint.
    function _mint(address account_, uint256 amount_) private {
        _totalSupply += amount_;
        uint256 adjustedAmount = amount_.div(cumulativeAdjustmentFactor);
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] += amount_;
        } else {
            _balances[account_] += adjustedAmount;
        }
        emit Transfer(address(0), account_, amount_);
    }
    
    /// @notice Burns the `amount_` tokens from an `account_`, reducing the total supply.
    /// @param account_ Account address.
    /// @param amount_ Amount of tokens to burn.
    function _burn(address account_, uint256 amount_) private {
        _totalSupply -= amount_;
        uint256 adjustedAmount = amount_.div(cumulativeAdjustmentFactor);
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] -= amount_;
        } else {
            _balances[account_] -= adjustedAmount;
        }
        emit Transfer(account_, address(0), amount_);
    }

    /// @notice Takes the sales commission and transfers it to the balance of the contract.
    /// @param from_ Token sender.
    /// @param amount_ Amount of tokens to transfer.
    /// @return Amount of tokens to transfer including the sales commission.
    function _takeSalesCommission(address from_, uint256 amount_) private returns (uint256) {
        uint256 commissionAmount = amount_ * percentageOfSalesCommission / BASE_PERCENTAGE;
        if (commissionAmount > 0) {
            unchecked {
                _balances[address(this)] += commissionAmount;
            }
            emit Transfer(from_, address(this), commissionAmount);
        }
        return amount_ - commissionAmount;
    }

    /// @notice Determines whether tokens can be sent between sender 
    /// and receiver when trading is not enabled.
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @return Boolean value indicating whether tokens can be sent.
    function _hasLimits(address from_, address to_) private view returns (bool) {
        return
            !hasRole(LIQUIDITY_PROVIDER_ROLE, from_) &&
            !hasRole(LIQUIDITY_PROVIDER_ROLE, to_);
    }

    /// @notice Retrieves the total supply of burn-protected accounts.
    /// @return supply_ Total supply of burn-protected accounts.
    function _totalSupplyOfBurnProtectedAccounts() private view returns (uint256 supply_) {
        uint256 length = _burnProtectedAccounts.length();
        for (uint256 i = 0; i < length; ) {
            unchecked {
                supply_ += _balances[_burnProtectedAccounts.at(i)];
                i++;
            }
        }
    }
}
