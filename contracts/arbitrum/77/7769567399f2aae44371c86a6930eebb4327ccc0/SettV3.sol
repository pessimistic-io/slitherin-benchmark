// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Math.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniswapV3Pool.sol";

import "./IController.sol";
import "./IBorrower.sol";
import "./IUniswapV3BaseStrategy.sol";
import "./IAddressProvider.sol";
import "./ILendVault.sol";
import "./IOracle.sol";
import "./IWETH.sol";
import "./IStrategyVault.sol";
import "./BlockNonEOAUpgradeable.sol";
import "./AccessControl.sol";
import "./AddressArray.sol";
import "./UintArray.sol";
import "./IRewards.sol";
import "./ISwapper.sol";

/**
 * @title SettV3
 * @notice This is the main vault contract that receives depositToken deposits, mints-burns shares in return, and allocates
 * to the underlying portfolio strategies.
 *
 *  @dev Source of Inspiration: https://github.com/iearn-finance/yearn-protocol/blob/develop/contracts/vaults/yVault.sol
 *  @dev Refer to the documentation/VAULT.MD for more information.
 */
contract SettV3 is
    ERC20Upgradeable,
    BlockNonEOAUpgradeable,
    AccessControl,
    PausableUpgradeable,
    IStrategyVault
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using AddressArray for address[];
    using UintArray for uint[];

    /// @notice Underlying token address that the vault receives as a deposit
    address public depositToken;

    /// @notice Array of strategies that the vault deposits user funds into
    address[] public strategies;

    /// @notice Array representing the allocation of funds to each strategy
    uint256[] public strategyAllocation;

    /// @notice The harvest time of the last epoch harvest
    uint public previousHarvestTimeStamp;

    /// @notice Price per share at most recent epoch harvest
    uint public waterMark;

    /// @notice Performance fee charged by the protocol
    uint public performanceFee;

    /// @notice Admin fee charged by the protocol
    uint public adminFee;

    /// @notice Withdrawal fee charged by the protocol
    uint public withdrawalFee;

    /// @notice What fraction of the fee that goes to governance, the rest goes to the reserve
    uint public governanceFee;

    /// @notice Mapping from strategy to amount of token that has been deposited into it
    mapping(address => uint) public deposited;

    /// @notice Mapping from strategy to amount of tokens that have been withdrawn from it
    mapping(address => uint) public withdrawn;

    /// @notice Number of positions-investors held by the vault
    uint public numPositions;

    /// @notice Maximum number of strategies that the vault can have
    uint public constant maxStrategies = 5;

    /// @notice Maximum percentage fee that can be given to admin
    uint public constant maxFee = PRECISION;

    mapping(address => bool) internal hasPosition;

    uint internal constant secondsPerYear = 31449600;

    string internal secondName;

    event EpochHarvest(
        uint waterMark,
        uint fee,
        uint sharesMinted,
        uint256 totalSupply
    );

    event Deposit(
        address indexed user,
        uint tokens,
        uint shares,
        uint pricePerShare
    );

    event Withdraw(
        address indexed user,
        uint tokens,
        uint shares,
        uint pricePerShare
    );

    /**
     * @notice Initializes the contract
     * @dev This is an upgradable contract
     * @param _strategies Array of addresses that sets up the Liquidity Pool Strategey addresses that couples the controller-strategies to the vault
     * @param _strategyAllocation Array of integers that initializes the above mapped strategies allocations
     */
    function initialize(
        address _provider,
        address _depositToken,
        string memory name,
        string memory symbol,
        address[] memory _strategies,
        uint256[] memory _strategyAllocation
    ) public initializer {
        __AccessControl_init(_provider);
        __BlockNonEOAUpgradeable_init(_provider);
        __Pausable_init();

        // Input validaiton
        ERC20(_depositToken).name();
        for (uint i = 0; i<_strategies.length; i++) {
            IBorrower(_strategies[i]).getDebts();
        }

        // Initialize contract variables
        depositToken = _depositToken;
        __ERC20_init(name, symbol);
        waterMark = getPricePerFullShare();
        previousHarvestTimeStamp = block.timestamp;
        strategies = _strategies;
        strategyAllocation = _strategyAllocation;

        performanceFee = 2 * PRECISION/10; // Performance fee is 20%
        adminFee = 2 * PRECISION/100; // Admin fee is 2%
        withdrawalFee = PRECISION / 1000; // Withdrawal fee is 0.1%
        governanceFee = 2 * PRECISION / 100; // Governance gets 2% of all fee
        require(_strategies.length<=maxStrategies, "Too many wants");
        require(_strategyAllocation.length == _strategies.length, "E37");

        // Paused on launch
        _pause();
    }

    /// ===== View Functions =====

    /**
     * @notice Gets the current version of the vault
     */
    function version() public pure returns (string memory) {
        return "1.0";
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        if (bytes(secondName).length==0) {
            return super.name();
        }
        return secondName;
    }

    /**
     * @notice Get an array of all the strategies that the vault deposits into
     */
    function getStrategies() external view returns (address[] memory strats) {
        strats = strategies.copy();
    }

    /**
     * @notice Get an array representing the allocations of funds to each strategy
     */
    function getStrategyAllocations() external view returns (uint[] memory allocations) {
        allocations = strategyAllocation.copy();
    }

    /**
     * @notice Gets the price per share of a vault
     */
    function getPricePerFullShare() public view virtual returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balance().mul(1e18).div(totalSupply());
    }

    /**
     * @notice Gets the price per share of a vault
     */
    function getPricePerFullShareOptimized() public virtual returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balanceOptimized().mul(1e18).div(totalSupply());
    }

    /**
     * @notice Calculates the amount of tokens a user will get after withdrawing fully
     * @param user the address of the user to get the withdrawable
     */
    function getWithdrawable(
        address user
    ) public view returns (uint) {
        uint _shares = balanceOfWithRewards(user);
        uint fee = Math.min(_calculateFee(getPricePerFullShare())+withdrawalFee, maxFee);
        uint sharesAsFee = (_shares * fee) / PRECISION;
        _shares -= sharesAsFee;
        uint vaultBalance = balance();
        return (vaultBalance.mul(_shares)).div(Math.max(1, totalSupply()));
    }

    /**
     * @notice Return the total balance of the deposit token within the system
     * @dev Sums the balance in the Sett, the Controller, and the Strategy
     */
    function balance() public view virtual returns (uint256) {
        int256 _totalBalance = 0;
        uint256 _depositTokenBalance = IERC20(depositToken).balanceOf(
            address(this)
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            _totalBalance += IBorrower(strategies[i]).balance();
        }
        return uint(_totalBalance) + _depositTokenBalance;
    }

    /**
     * @notice Return the user balance of minted ERC20 tokens + Rewards
     * @dev Sums the contract balance + staked balance
     */    
    function balanceOfWithRewards(address _user) public view returns (uint256 userBalance){
        userBalance += balanceOf(_user);
        IRewards rewards = IRewards(provider.rewardDistribution());        
        try rewards.balanceOf(address(this), _user, false, address(this)) {
            userBalance += rewards.balanceOf(address(this), _user, false, address(this));
        }catch{}                
    } 

    /**
     * @notice Return the total balance of the deposit token within the system
     * @dev Sums the balance in the Sett, the Controller, and the Strategy
     */
    function balanceOptimized() public virtual returns (uint256) {
        int256 _totalBalance = 0;
        uint256 _depositTokenBalance = IERC20(depositToken).balanceOf(
            address(this)
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            _totalBalance += IBorrower(strategies[i]).balanceOptimized();
        }
        return uint(_totalBalance) + _depositTokenBalance;
    }

    /**
     * @notice Calculates the tvl, capacity and current depositable amount for the vault
     * @return depositable is the current max amount of depositToken that can be deposited into the vault
     * @return tvl is the total funds in possesion of a vault's strategies, including deposited
     * tokens and borrowed tokens
     * @return capacity is the highest tvl that the vault can achieve by depositing into strategies
     * and borrowing from the LendVault
     */
    function vaultCapacity() external view returns (uint depositable, uint tvl, uint capacity) {
        address[][] memory borrowableTokens = new address[][](strategies.length);
        uint[][] memory temp = new uint[][](strategies.length);
        uint totalAllocation;
        uint leverageSum;
        for (uint i = 0; i<strategies.length; i++) {
            (address[] memory strategyTokens, uint[] memory amounts) = ILendVault(provider.lendVault()).getBorrowerTokens(strategies[i]);
            borrowableTokens[i] = strategyTokens;
            temp[i] = amounts;
            (uint leverage,,,,) = IUniswapV3BaseStrategy(strategies[i]).parameters();
            leverageSum+=strategyAllocation[i] * leverage;
            totalAllocation+=strategyAllocation[i];
            tvl+=IBorrower(strategies[i]).tvl();
        }
        (address[] memory tokens,) = _combine(borrowableTokens, temp);
        uint averageLeverage = leverageSum / totalAllocation;

        uint totalBorrowable;
        for (uint i = 0; i<tokens.length; i++) {
            uint borrowable = _getBorrowable(tokens[i]);
            totalBorrowable+=IOracle(provider.oracle()).getValueInTermsOf(tokens[i], borrowable, depositToken);
        }
        uint approximateDepositable = (totalBorrowable * PRECISION * PRECISION / averageLeverage) / PRECISION;

        depositable = uint(int(approximateDepositable) + _correctDepositable(approximateDepositable, approximateDepositable));

        (address[] memory borrowTokens, uint[] memory borrowAmounts) = _simulateDeposits(depositable);

        uint totalBorrowed;
        for (uint i = 0; i<borrowTokens.length; i++) {
            totalBorrowed+=IOracle(provider.oracle()).getValueInTermsOf(borrowTokens[i], borrowAmounts[i], depositToken);
        }

        capacity = tvl + depositable + totalBorrowed;
    }


    /// ===== Public Actions =====

    /**
     * @notice Deposit a token other than the deposit token of the vault
     * The token will be swapped with the vault's deposit token using the provided slippage value by the swapper
     * @param _token The token being used to deposit instead of the deposit token
     * @param _amount Amount of token to use to make the deposit
     * @param _slippage the slippage value used by the swapper
     * @dev slippage represents how much of a loss can be accepted
     * Max slippage is PRECISION, in which case all funds can be lost
     * Min slippage is 0, representing no loss of funds
     */
    function depositOtherToken(address _token, uint256 _amount, uint256 _slippage) public payable whenNotPaused onlyEOA {
        require(msg.value==0 || _amount==0, "E39");
        uint256 startBalance = balanceOptimized();
        if (msg.value>0) {
            require(_token==provider.networkToken(), "E40");
            _amount = msg.value;
            IWETH(payable(provider.networkToken())).deposit{value: _amount}();
        } else {
            IERC20(_token).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        if (_token!=depositToken) {
            ISwapper swapper = ISwapper(provider.swapper());
            _approveSpender(address(swapper), _token, _amount);
            uint amountOut = swapper.swapExactTokensForTokens(_token, _amount, depositToken, _slippage);
            _deposit(amountOut, startBalance);
        } else {
            _deposit(_amount, startBalance);
        }
    }

    /**
     * @notice Deposit assets into the Sett, and return corresponding shares to the user
     * @param _amount the amount of underlying currency to deposit
     */
    function deposit(uint256 _amount) public payable whenNotPaused onlyEOA{
        uint256 startBalance = balanceOptimized();
        require(msg.value==0 || _amount==0, "E39");
        if (msg.value>0) {
            require(depositToken==provider.networkToken(), "E40");
            _amount = msg.value;
            IWETH(payable(provider.networkToken())).deposit{value: _amount}();
        } else {
            IERC20(depositToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        _deposit(_amount, startBalance);
    }

    /**
     * @notice Convenience function: Deposit entire balance of asset into the Sett, and return corresponding shares to the user
     */
    function depositAll() external whenNotPaused onlyEOA{
        uint256 startBalance = balanceOptimized();
        uint256 depositAmount = IERC20(depositToken).balanceOf(msg.sender);
        IERC20(depositToken).safeTransferFrom(
            msg.sender,
            address(this),
            depositAmount
        );
        _deposit(depositAmount, startBalance);
    }

    /**
     * @notice Withdraws funds from the Sett-Vault and burn shares of the user
     * @dev returns the corresponding amount of the share value in underlying currency to the user.
     * @dev Fee in the form of shares will be given to governance and in the form of tokens to the reserve
     * @param _shares the amount of shares to burn for underlying currency
     */
    function withdraw(uint256 _shares) public whenNotPaused onlyEOA{
        _rewardWithdraw(_shares); 
        _withdraw(_shares);
    }

    /// @notice Convenience function: Withdraw all shares of the sender
    function withdrawAll() external whenNotPaused onlyEOA{
        _rewardWithdraw(balanceOfWithRewards(msg.sender));             
        _withdraw(balanceOf(msg.sender));
    }

    /// ===== Permissioned Actions: Governance =====

    /**
     * @notice Sets the fees to be charged by the protocol
     * @dev Only governance can call this function
     * @param performance The performance fee percentage to be charged by the vault
     * The performance fee is only applied if the vault has had a positive ROI since the last epoch harvest
     * @param admin The administration fee to be charged by the vault
     * @param withdrawal This is a low penalty fee for withdrawing, it is supposed to disincentivize withdrawal attacks.
     */
    function setFees(uint performance, uint admin, uint withdrawal) external restrictAccess(GOVERNOR) {
        require(performance<PRECISION, "Performance fee too high");
        require(admin<PRECISION, "Admin fee too high");
        require(withdrawal<PRECISION, "Withdrawal fee too high");
        performanceFee = performance;
        adminFee = admin;
        withdrawalFee = withdrawal;
    }

    /**
     * @notice Sets the governance fee
     * The governance fee represents what percentage of the fee goes to the governance address
     */
    function setGovernanceFee(uint _governanceFee) external restrictAccess(GOVERNOR) {
        require(_governanceFee<PRECISION, "Governance fee too high");
        governanceFee = _governanceFee;
    }

    /**
     * @notice This function sets the funds allocation in the strategies
     * @dev This is a permissioned function, the allocation can only be set by the governance.
     * @dev If a new allocation is set, funds are withdrawn from the strategies and redeposited based on the new allocation.
     * @dev The allocation set here will also determine how the deposits and withdrawals are made proportionally to the whole portfolio composition.
     * @param _strategies The strategies that the vault will deposit into
     * @param _strategiesAllocation The allocation of deposits into each strategy
     */
    function setStrategiesAndAllocations(
        address[] memory _strategies,
        uint256[] memory _strategiesAllocation
    ) public restrictAccess(GOVERNOR) {
        require(
            _strategiesAllocation.length == _strategies.length,
            "E37"
        );

        //TRIGGER WITHDRAW AND THEN NEW EARN
        for (uint256 i = 0; i < strategies.length; i++) {
            if (IBorrower(strategies[i]).balance()>0) {
                IController(provider.controller()).withdrawAll(strategies[i]);
            }
        }
        
        //REBALANCE ALLOCATIONS
        strategyAllocation = _strategiesAllocation;
        strategies = _strategies;
        earn();
    }

    /**
     * @notice Adds the deposited amount for a deprecated strategy to the new version and triggers
     * contract state migration via Controller
     * @dev withdrawn is not included in this function since the strategy now tracks withdrawn amounts
     */
    function migrateStrategy(address _oldAddress, address _newAddress) external restrictAccess(GOVERNOR) {
        deposited[_newAddress]+=deposited[_oldAddress];
        IController(provider.controller()).migrateStrategy(_oldAddress, _newAddress);
    }

    /**
     * @notice Reset strategy pnl to 0
     */
    function resetStrategyPnl(address _strategy) external restrictAccess(GOVERNOR) {
        deposited[_strategy] = uint(IBorrower(_strategy).balance());
        IController(provider.controller()).resetStrategyPnl(_strategy);
    }

    /**
     * @notice Change the name of the contract
     */
    function rename(string memory newName) external restrictAccess(GOVERNOR) {
        secondName = newName;
    }

    /// ===== Permissioned Functions: Trusted Actors =====

    /**
     * @notice This function harvests the fees from all strategies
     * @dev Can only be called by governance or the keeper
     * @dev This function is usually called by the keeper at the end of an epoch every 7 days.
     * @dev It mints shares to the governance address and sends a few tokens to the reserve.
     * The percentage given to goveranance and reserve are based on governanceFee
     */
    function epochHarvest() public whenNotPaused restrictAccess(GOVERNOR | KEEPER) {
        _harvest();
        _earn(IERC20(depositToken).balanceOf(address(this)));
        uint fee = Math.min(_calculateFee(getPricePerFullShareOptimized()), maxFee);
        previousHarvestTimeStamp = block.timestamp;
        uint sharesToMint = (totalSupply() * fee) / PRECISION;
        _mintFeeShares(sharesToMint);
        waterMark = getPricePerFullShare();
        emit EpochHarvest(
            waterMark,
            fee,
            sharesToMint,
            totalSupply()
        );
    }

    /**
     * @notice Transfer the underlying available tokens to be used in the strategies
     * @dev The controller will deposit into the Strategy for yield-generating activities
     */
    function earn() public whenNotPaused restrictAccess(GOVERNOR) {
        _earn(IERC20(depositToken).balanceOf(address(this)));
    }

    /**
     * @notice Transfer an amount of the specified token from the vault to the sender.
     * @dev This is purely a safeguard.
     * @param _token The address of the token that is stuck and should be transfered
     * @param _amount The amount that should be sent to the caller
     */
    function inCaseTokensGetStuck(address _token, uint256 _amount) public restrictAccess(GOVERNOR) {
        require(_amount>0, "E21");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// ===== Internal Implementations =====

    /**
     * @notice Transfer the specified amount of depositToken to the strategies based on allocations
     */
    function _earn(uint amount) internal {
        uint256 totalAllocation = strategyAllocation.sum();
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategyAllocation[i] > 0) {
                uint256 _allocation = (strategyAllocation[i] * amount).div(totalAllocation);
                IERC20(depositToken).safeTransfer(
                    strategies[i],
                    _allocation
                );
                deposited[strategies[i]]+=_allocation;
                IController(provider.controller()).earn(strategies[i]);
            }
        }
    }

    /**
     * @notice Harvests all strategies under the vault
     */
    function _harvest() internal virtual {
        for (uint i = 0; i < strategies.length; i++) {
            IController(provider.controller()).harvest(strategies[i]);
        }
    }

    /**
     * @notice Deposit assets into the Sett, and return corresponding shares to the user
     * @param _depositAmount the amount of underlying currency to deposit
     */
    function _deposit(uint256 _depositAmount, uint256 _pool) internal virtual {
        _earn(_depositAmount);
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _depositAmount;
        } else {
            shares = (_depositAmount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        if (!hasPosition[msg.sender]) {
            hasPosition[msg.sender] = true;
            numPositions += 1;
        }
                
        IRewards rewards = IRewards(provider.rewardDistribution());
        (, bool poolExists) = rewards.getPoolId(address(this), false, address(this));
        if(poolExists){
            approve(provider.rewardDistribution(), shares);                     
            try rewards.deposit(address(this), shares, msg.sender, false, address(this)){} catch {}
        }
        
        emit Deposit(
            msg.sender,
            _depositAmount,
            shares,
            getPricePerFullShare()
        );
    }

    /**
     * @notice Withdraws funds from the Sett-Vault and burn shares of the user
     * @dev returns the corresponding amount of the share value in underlying currency to the user.
     * @param _shares the amount of shares to exchange and burn for underlying currency
     */
    function _withdraw(uint256 _shares) internal virtual {
        if (_shares == balanceOf(msg.sender)) {
            hasPosition[msg.sender] = false;
            // numPositions -= 1;
        }
        uint fee = msg.sender!=provider.governance()?Math.min(_calculateFee(getPricePerFullShareOptimized())+withdrawalFee, maxFee):0;
        uint sharesAsFee = (_shares * fee) / PRECISION;
        uint governanceShares = sharesAsFee * governanceFee / PRECISION;
        uint reserveShares = sharesAsFee - governanceShares;
        uint userShares = _shares - sharesAsFee;

        uint _shares_calc = userShares + reserveShares;
        uint tokensWithdrawn = _withdrawFromStrategies(_shares_calc);
        _burn(msg.sender, _shares);
        _mint(provider.governance(), governanceShares);

        IERC20(depositToken).safeTransfer(msg.sender, tokensWithdrawn * userShares / Math.max(1, _shares_calc));
        IERC20(depositToken).safeTransfer(provider.reserve(), tokensWithdrawn * reserveShares / Math.max(1, _shares_calc));
        uint pps = getPricePerFullShareOptimized();
        emit Withdraw(
            msg.sender,
            tokensWithdrawn * userShares / Math.max(1, _shares_calc),
            _shares,
            pps
        );
    }

    /// ===== Pause Vault Actions =====

    /**
     * @notice Can pause the vault
     * @dev Only authorized actors can trigger this call
     */
    function pause() external restrictAccess(GOVERNOR)  {
        _pause();
    }

    /**
     * @notice Can un-pause the vault
     * @dev Only authorized actors can trigger this call
     */
    function unpause() external restrictAccess(GOVERNOR) {
        _unpause();
    }

    /// ===== Internal helper functions =====

    /**
     * @notice Calculates the total fee percentage based on watermark and current price per share
     * @return fee The fee that can be charged to the vault for its performance. Admin + Performance Fee
     */
    function _calculateFee(uint pricePerShare) internal view returns (uint fee) {
        if (pricePerShare > waterMark) {
            uint priceIncrease = pricePerShare - waterMark;
            fee =
                (priceIncrease * performanceFee) /
                (waterMark > 0 ? waterMark : 10 ** 18);
        }

        uint timeSinceEpoch = block.timestamp - previousHarvestTimeStamp;
        uint adminFeeNow = (adminFee * timeSinceEpoch) / (secondsPerYear);
        fee += adminFeeNow;
    }

    /**
     * @notice Mints shares for the governance and sends deposit token to reserve
     * @dev The reserve is not supposed to hold strategy vault tokens, hence they
     * are not minted here, but instead, tokens are directly sent to the reserve
     * corresponding to how many shares would have been minted
     */
    function _mintFeeShares(uint shares) internal {
        uint governanceShares = shares * governanceFee / PRECISION;
        uint reserveShares = shares - governanceShares;
        uint256 reserveTokens = _withdrawFromStrategies(reserveShares);
        _mint(provider.governance(), governanceShares);
        IERC20(depositToken).safeTransfer(provider.reserve(), reserveTokens);
    }

    /**
     * @notice Withdraws a desired amount of depositToken from the strategies
     * @param shares The amount of tokens that are needed to be withdrawn
     * @return tokensWithdrawn The amount of depositToken that was retrieved from the strategies
     */
    function _withdrawFromStrategies(uint shares) internal returns (uint tokensWithdrawn) {
        uint balanceStart = IERC20(depositToken).balanceOf(address(this));
        tokensWithdrawn = balanceStart * shares / totalSupply();
        for (uint256 i = 0; i < strategies.length; i++) {
            IController(provider.controller()).withdraw(strategies[i], shares * PRECISION / totalSupply());
        }
        tokensWithdrawn+=IERC20(depositToken).balanceOf(address(this)) - balanceStart;
    }

    /**
     * @notice Given a two dimensional array of tokens and amounts, gives a one
     * dimensional list of unique tokens and the combined amounts for the tokens
     */
    function _combine(
        address[][] memory strategyTokens,
        uint[][] memory strategyBorrowAmounts
    ) internal pure returns (address[] memory tokens, uint[] memory amounts) {
        uint maxTokens;
        for (uint i = 0; i<strategyTokens.length; i++) {
            maxTokens+=strategyTokens[i].length;
        }
        address[] memory tempTokens = new address[](maxTokens);
        uint[] memory tempAmounts = new uint[](maxTokens);
        uint tempTokensIndex;
        for (uint i = 0; i<strategyTokens.length; i++) {
            for (uint j = 0; j<strategyTokens[i].length; j++) {
                uint tokenIndex = tempTokens.findFirst(strategyTokens[i][j]);
                if (tokenIndex==tempTokens.length) {
                    tempTokens[tempTokensIndex] = strategyTokens[i][j];
                    tempAmounts[tempTokensIndex] = strategyBorrowAmounts[i][j];
                    tempTokensIndex+=1;
                } else {
                    tempAmounts[tokenIndex]+=strategyBorrowAmounts[i][j];
                }
            }
        }
        tokens = new address[](tempTokensIndex);
        amounts = new uint[](tempTokensIndex);
        for (uint i = 0; i<tempTokensIndex; i++) {
            tokens[i] = tempTokens[i];
            amounts[i] = tempAmounts[i];
        }
    }
    
    /**
     * @notice Simulates a deposit of a given amount to the vault and returns the tokens that will be borrowed
     * by the underlying strategies
     */
    function _simulateDeposits(uint amount) internal view returns (address[] memory tokens, uint[] memory amounts) {
        ILendVault lendVault = ILendVault(provider.lendVault());
        address[][] memory strategyTokens = new address[][](strategies.length);
        uint[][] memory strategyBorrowAmounts = new uint[][](strategies.length);
        
        uint256 totalAllocation = strategyAllocation.sum();
        address[] memory lendVaultTokens = lendVault.getSupportedTokens();
        uint[] memory availableLendVaultTokens = new uint[](lendVaultTokens.length);
        for (uint i = 0; i<lendVaultTokens.length; i++) {
            availableLendVaultTokens[i] = _getBorrowable(lendVaultTokens[i]);
        }
        for (uint i = 0; i<strategyAllocation.length; i++) {
            (strategyTokens[i], strategyBorrowAmounts[i]) = IBorrower(strategies[i]).getBorrowForDeposit(
                strategyAllocation[i] * amount / totalAllocation,
                lendVaultTokens,
                availableLendVaultTokens
            );
            for (uint j = 0; j<lendVaultTokens.length; j++) {
                uint idx = strategyTokens[i].findFirst(lendVaultTokens[j]);
                if (idx<strategyBorrowAmounts[i].length) {
                    availableLendVaultTokens[j]-=Math.min(strategyBorrowAmounts[i][idx], availableLendVaultTokens[j]);
                }
            }
        }

        (tokens, amounts) = _combine(strategyTokens, strategyBorrowAmounts);
    }

    /**
     * @notice Simulates vault deposit with given amount and returns a positive adjustment if more
     * can be deposited and negative adjustment if the deposit amount is too high
     */
    function _correctDepositable(uint amount, uint prevAdjustment) internal view returns (int adjustment) {
        IOracle oracle = IOracle(provider.oracle());
        (address[] memory borrowTokens, uint[] memory borrowAmounts) = _simulateDeposits(amount);
        int[] memory adjustments = new int[](borrowTokens.length);
        bool canBorrowMore = true;

        for (uint i = 0; i<borrowTokens.length; i++) {
            uint borrowable = _getBorrowable(borrowTokens[i]);
            if (borrowAmounts[i]>borrowable) {
                canBorrowMore = false;
                uint diff = borrowAmounts[i] - borrowable;
                uint inTermsOfDepositToken = oracle.getValueInTermsOf(borrowTokens[i], diff, depositToken);
                adjustments[i] = -int(inTermsOfDepositToken);
            } else {
                uint diff = borrowable - borrowAmounts[i];
                uint inTermsOfDepositToken = oracle.getValueInTermsOf(borrowTokens[i], diff, depositToken);
                adjustments[i] = int(inTermsOfDepositToken);
            }
        }

        for (uint i = 0; i<borrowTokens.length; i++) {
            if ((canBorrowMore && adjustments[i]>adjustment) || (!canBorrowMore && adjustments[i]<adjustment)) {
                adjustment = adjustments[i];
            }
        }

        adjustment = canBorrowMore?int(prevAdjustment/2):-int(prevAdjustment/2);
        uint adjustmentUsd = oracle.getValue(depositToken, adjustment>0?uint(adjustment):uint(-adjustment));

        if (adjustment==0 || adjustmentUsd<10**18) {
            adjustment = 0;
        } else {
            adjustment+=_correctDepositable(uint(int(amount) + adjustment), adjustment>0?uint(adjustment):uint(-adjustment));
        }
    }

    /**
     * @notice Calculates the amount of a given token that can currently be borrowed from the lend vault
     */
    function _getBorrowable(address token) internal view returns (uint borrowable) {
        ILendVault lendVault = ILendVault(provider.lendVault());
        uint totalAssets = lendVault.totalAssets(token);
        uint utilizationCap = lendVault.maxUtilization();
        uint usableTokens = utilizationCap * totalAssets / PRECISION;
        uint usedTokens = lendVault.getTotalDebt(token);
        borrowable = usableTokens>usedTokens?usableTokens - usedTokens:0;
    }

    function _rewardWithdraw(uint _shares) internal {
        IRewards rewards = IRewards(provider.rewardDistribution());  
        (, bool poolExists) = rewards.getPoolId(address(this), false, address(this));
        if(poolExists){
            uint256 balanceInRewards = rewards.balanceOf(address(this), msg.sender, false, address(this));
            uint256 balanceInContract = balanceOf(msg.sender);        
            uint256 balanceToWithdrawFromMasterChef = _shares - balanceInContract;
            if(balanceInRewards > 0 && balanceToWithdrawFromMasterChef > 0){
                try rewards.withdraw(address(this), balanceToWithdrawFromMasterChef, msg.sender, false, address(this)){} catch {}
            }
        }
    }

    /**
     * @notice Set approval to max for spender if approval isn't high enough
     */
    function _approveSpender(address spender, address token, uint amount) internal {
        uint allowance = IERC20(token).allowance(address(this), spender);
        if(allowance<amount) {
            IERC20(token).safeIncreaseAllowance(spender, 2**256-1-allowance);
        }
    }

    receive() external payable {
        IWETH(payable(provider.networkToken())).deposit{value: address(this).balance}();
    }
}

