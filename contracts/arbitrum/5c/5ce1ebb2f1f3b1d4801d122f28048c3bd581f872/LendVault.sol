// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ILendVault.sol";
import "./IBorrower.sol";
import "./IReserve.sol";
import "./ISwapper.sol";
import "./IAddressProvider.sol";
import "./IWETH.sol";
import "./AddressArray.sol";
import "./ERC1155Upgradeable.sol";
import "./Initializable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./Address.sol";
import "./OwnableUpgradeable.sol";
import "./BlockNonEOAUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControl.sol";
import "./LendVaultStorage.sol";

/**
 * @notice LendVault manages the lending of multiple tokens
 * @dev In order to allow a token to be deposited and borrowed:
 * - initializeToken needs to be called with IRM data for the tokens that will be used
 * - setCreditLimits needs to be called to allow borrowers to borrow the tokens
 * - Non EOA accounts are blocked by default, setWhitelistUsers needs to be called to allow contract accounts to make transactions
 */
contract LendVault is 
    ILendVault,
    ERC1155Upgradeable,
    AccessControl,
    BlockNonEOAUpgradeable,
    ReentrancyGuardUpgradeable,
    LendVaultStorage 
{
    using SafeERC20 for IERC20;
    using AddressArray for address[];
    using Address for address;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     */
    function initialize(address _addressProvider, uint _healthThreshold, uint _maxUtilization, uint _slippage, uint _deleverFee) external initializer {
        __ERC1155_init("LendVault");
        __BlockNonEOAUpgradeable_init(_addressProvider);
        __AccessControl_init(_addressProvider);
        __ReentrancyGuard_init();
        require(_slippage<=PRECISION, "E12");
        require(_deleverFee<=1e18, "E33");
        require(_maxUtilization<PRECISION, "E36");
        healthThreshold = _healthThreshold;
        maxUtilization = _maxUtilization;
        slippage = _slippage;
        deleverFeeETH = _deleverFee;
        address[] memory initialWhitelist = new address[](1);
        initialWhitelist[0] = provider.reserve();
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        setWhitelistUsers(initialWhitelist, allowed);
    }

    function _checkTokenInitialized(address token) internal view {
        require(irmData[token].initialized, "E24");
    }

    modifier tokenInitialized(address token) {
        _checkTokenInitialized(token);
        _;
    }

    /// @inheritdoc ILendVault
    function initializeToken(address token, IRMData memory data) external restrictAccess(GOVERNOR) {
        require(data.optimalUtilizationRate<=10*PRECISION, "E25");
        require(data.baseBorrowRate<=10*PRECISION, "E26");
        require(data.slope1<=10*PRECISION, "E27");
        require(data.slope2<=10*PRECISION, "E28");
        if (data.initialized && !supportedTokens.exists(token)) {
            supportedTokens.push(token);
        }
        if (!data.initialized) {
            uint index = supportedTokens.findFirst(token);
            if (index<supportedTokens.length) {
                supportedTokens[index] = supportedTokens[supportedTokens.length-1];
                supportedTokens.pop();
            }
        }
        irmData[token] = data;
    }

    // ---------- Owner Functions ----------

    /// @inheritdoc ILendVault
    function setCreditLimit(address borrower, address[] memory tokens, uint[] memory _creditLimits) external restrictAccess(GOVERNOR) {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            tokenData[token].totalCreditLimit-=creditLimits[token][borrower];
            require(tokenData[token].totalCreditLimit+_creditLimits[i]<=PRECISION, "E29");
            creditLimits[token][borrower] = _creditLimits[i];
            tokenData[token].totalCreditLimit+=_creditLimits[i];

            if (_creditLimits[i]>0) {
                // Add borrower to list of borrowers for token
                if (!tokenBorrowers[token].exists(borrower)) {
                    tokenBorrowers[token].push(borrower);
                }

                // Add token to list of borrowed tokens for borrower
                if (!borrowerTokens[borrower].exists(token)) {
                    borrowerTokens[borrower].push(token);
                }
            } else {
                // Remove borrower if credit limit is 0
                uint borrowerIndex = tokenBorrowers[token].findFirst(borrower);
                if (borrowerIndex<tokenBorrowers[token].length) {
                    tokenBorrowers[token][borrowerIndex] = tokenBorrowers[token][tokenBorrowers[token].length-1];
                    tokenBorrowers[token].pop();
                }

                // Remove token if credit limit is 0
                uint tokenIndex = borrowerTokens[borrower].findFirst(token);
                if (tokenIndex<borrowerTokens[borrower].length) {
                    borrowerTokens[borrower][tokenIndex] = borrowerTokens[borrower][borrowerTokens[borrower].length-1];
                    borrowerTokens[borrower].pop();
                }

            }
        }
    }
    
    /// @inheritdoc ILendVault
    function setHealthThreshold(uint _healthThreshold) external restrictAccess(GOVERNOR) {
        healthThreshold = _healthThreshold;
    }
    
    /// @inheritdoc ILendVault
    function setMaxUtilization(uint _maxUtilization) external restrictAccess(GOVERNOR) {
        require(_maxUtilization<PRECISION, "E36");
        maxUtilization = _maxUtilization;
    }
    
    /// @inheritdoc ILendVault
    function setSlippage(uint _slippage) external restrictAccess(GOVERNOR) {
        require(_slippage<=PRECISION, "E12");
        slippage = _slippage;
    }
    
    /// @inheritdoc ILendVault
    function setDeleverFee(uint _deleverFee) external restrictAccess(GOVERNOR) {
        require(_deleverFee<=1e18, "E33");
        deleverFeeETH = _deleverFee;
    }

    // ---------- View Functions ----------

    /// @inheritdoc ILendVault
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens.copy();
    }
    
    /// @inheritdoc ILendVault
    function getBorrowerTokens(address borrower) external view returns (address[] memory tokens, uint[] memory amounts) {
        tokens = borrowerTokens[borrower].copy();
        amounts = new uint[](tokens.length);
        for (uint i = 0; i<tokens.length; i++) {
            amounts[i] = getDebt(tokens[i], borrower);
        }
    }

    /// @inheritdoc ILendVault
    function getTokenBorrowers(address token) external view returns (address[] memory borrowers, uint[] memory amounts) {
        borrowers = tokenBorrowers[token].copy();
        amounts = new uint[](borrowers.length);
        for (uint i = 0; i<borrowers.length; i++) {
            amounts[i] = getDebt(token, borrowers[i]);
        }
    }

    /// @inheritdoc ILendVault
    function balanceOf(address lender, address token) public view returns (uint shares) {
        shares = balanceOf(lender, uint(keccak256(abi.encodePacked(token))));
    }

    /// @inheritdoc ILendVault
    function tokenBalanceOf(address lender, address token) external view returns (uint amount) {
        uint shares = balanceOf(lender, uint(keccak256(abi.encodePacked(token))));
        uint totalTokens = totalAssets(token);
        amount = totalTokens * shares / Math.max(1, tokenData[token].totalShares);
    }

    /// @inheritdoc ILendVault
    function utilizationRate(address token) public view returns (uint utilization) {
        uint totalTokenAmount = totalAssets(token);
        uint totalDebt = getTotalDebt(token);
        return (totalDebt * PRECISION) / Math.max(1, totalTokenAmount);
    }

    /// @inheritdoc ILendVault
    function totalAssets(address token) public view returns (uint amount) {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        uint totalDebt = getTotalDebt(token);
        amount = tokenBalance + totalDebt;
    }

    /// @inheritdoc ILendVault
    function convertToShares(address token, uint amount) public view returns (uint shares) {
        uint totalTokenAmount = totalAssets(token);
        return Math.max(1, tokenData[token].totalShares) * amount / Math.max(1, totalTokenAmount);
    }

    /// @inheritdoc ILendVault
    function convertToAssets(address token, uint shares) public view returns (uint amount) {
        uint totalTokenAmount = totalAssets(token);
        return Math.max(1, totalTokenAmount) * shares / Math.max(1, tokenData[token].totalShares);
    }

    /// @inheritdoc ILendVault
    function getTotalDebt(address token) public view returns (uint totalDebt) {
        uint elapsedTime = block.timestamp - tokenData[token].lastInterestRateUpdate;
        uint interestAccrued = (tokenData[token].totalDebt * tokenData[token].interestRate * elapsedTime) / (PRECISION * 365 days);
        totalDebt = tokenData[token].totalDebt + interestAccrued;
    }

    /// @inheritdoc ILendVault
    function getDebt(address token, address borrower) public view returns (uint debt) {
        uint totalDebt = getTotalDebt(token);
        uint borrowerDebtShare = debtShare[token][borrower];
        debt = (borrowerDebtShare*totalDebt)/Math.max(1, tokenData[token].totalDebtShares);
    }

    /// @inheritdoc ILendVault
    function checkHealth(address borrower) external view returns (int health) {
        address[] memory tokens = new address[](borrowerTokens[borrower].length);   // Tokens borrowed by borrower
        uint[] memory amounts = new uint[](borrowerTokens[borrower].length);        // Debt amounts for borrowed tokens
        (address[] memory availableTokens, uint[] memory availableAmounts) = IBorrower(borrower).getAmounts();
        uint totalETHValue = ISwapper(provider.swapper()).getETHValue(availableTokens, availableAmounts);

        for (uint i = 0; i<borrowerTokens[borrower].length; i++) {
            address token = borrowerTokens[borrower][i];
            uint debt = getDebt(token, borrower);
            tokens[i] = token;
            amounts[i] = debt;
        }
        uint debtETHValue = ISwapper(provider.swapper()).getETHValue(tokens, amounts);
        health = (int(totalETHValue)-int(debtETHValue))*int(PRECISION)/int(Math.max(1, debtETHValue));
    }

    // ---------- Lender/Borrower Functions ----------

    /// @inheritdoc ILendVault
    function deposit(address token, uint amount) external payable onlyEOA nonReentrant tokenInitialized(token) {
        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("updateInterestRate(address)", token));
        uint shares = convertToShares(token, amount + msg.value);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        require(!(token!=provider.networkToken() && msg.value>0), "Wrong token");
        if(msg.value>0) {
            IWETH networkToken = IWETH(payable(provider.networkToken()));
            networkToken.deposit{value: msg.value}();
        }
        _mint(msg.sender, uint(keccak256(abi.encodePacked(token))), shares, "");
        tokenData[token].totalShares += shares;

        // Repay the funds borrowed from the reserve to provide instant liquidity
        uint reserveShares = balanceOf(provider.reserve(), token);
        if (reserveShares>0) {
            uint sharesToBurn = Math.min(reserveShares, shares);
            uint amountReturned = convertToAssets(token, sharesToBurn);
            _burn(provider.reserve(), uint(keccak256(abi.encodePacked(token))), sharesToBurn);
            tokenData[token].totalShares -= sharesToBurn;
            IERC20(token).safeTransfer(provider.reserve(), amountReturned);
        }
        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("updateInterestRate(address)", token));
        emit Deposit(token, msg.sender, amount, shares);
    }

    /// @inheritdoc ILendVault
    function withdrawShares(address token, uint shares) external onlyEOA nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        _withdraw(token, shares);
    }

    /// @inheritdoc ILendVault
    function withdrawAmount(address token, uint amount) external onlyEOA nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        uint shares = convertToShares(token, amount);
        _withdraw(token, shares);
    }

    /// @inheritdoc ILendVault
    function withdrawMax(address token) external onlyEOA nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        uint shares = balanceOf(msg.sender, token);
        _withdraw(token, shares);
    }

    /// @inheritdoc ILendVault
    function borrow(address token, uint amount) external nonReentrant tokenInitialized(token) {
        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("updateInterestRate(address)", token));
        uint shares = Math.max(1, tokenData[token].totalDebtShares) * amount / Math.max(1, tokenData[token].totalDebt);
        tokenData[token].totalDebt += amount;
        tokenData[token].totalDebtShares += shares;
        debtShare[token][msg.sender] += shares;
        IERC20(token).safeTransfer(msg.sender, amount);                
        /*LETS REVIEW THE CREDIT LIMIT PART LATER*/
        uint borrowed = debtShare[token][msg.sender]*tokenData[token].totalDebt/Math.max(1, tokenData[token].totalDebtShares);
        uint borrowedFraction = borrowed*PRECISION/(totalAssets(token));
        require(creditLimits[token][msg.sender]>=borrowedFraction, "E31");
        require(utilizationRate(token)<=maxUtilization, "E34");

        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("updateInterestRate(address)", token));
        emit Borrow(token, msg.sender, amount, shares);
    }

    /// @inheritdoc ILendVault
    function repayShares(address token, uint shares) external nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        _repay(token, shares);
    }

    /// @inheritdoc ILendVault
    function repayAmount(address token, uint amount) external nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        uint shares = amount*Math.max(1, tokenData[token].totalDebtShares)/Math.max(1, tokenData[token].totalDebt);
        _repay(token, shares);
    }

    /// @inheritdoc ILendVault
    function repayMax(address token) external nonReentrant tokenInitialized(token) {
        _updateInterestRate(token);
        uint balance = IERC20(token).balanceOf(msg.sender);
        uint debt = (debtShare[token][msg.sender] * tokenData[token].totalDebt) / Math.max(1, tokenData[token].totalDebtShares);
        uint sharesToRepay = Math.min(balance * debtShare[token][msg.sender]/Math.max(1, debt), debtShare[token][msg.sender]);
        _repay(token, sharesToRepay);
    }

    /// @inheritdoc ILendVault
    function kill(address borrower) external {
        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("kill(address)", borrower));
    }

    // ---------- Internal Helper Functions ----------

    function _updateInterestRate(address token) internal {
        provider.borrowerManager().functionDelegateCall(abi.encodeWithSignature("updateInterestRate(address)", token));
    }

    function _repay(address token, uint shares) internal {
        uint amount = shares*tokenData[token].totalDebt/Math.max(1, tokenData[token].totalDebtShares);
        tokenData[token].totalDebt -= amount;
        tokenData[token].totalDebtShares -= shares;
        debtShare[token][msg.sender] -= shares;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _updateInterestRate(token);
        emit Repay(token, msg.sender, amount, shares);
    }

    function _withdraw(address token, uint shares) internal {
        uint amount = convertToAssets(token, shares);
        _burn(msg.sender, uint(keccak256(abi.encodePacked(token))), shares);
        uint balance = IERC20(token).balanceOf(address(this));
        tokenData[token].totalShares -= shares;

        uint fee;
        if (amount<=balance) {
            IERC20(token).safeTransfer(msg.sender, amount);
        } else {
            uint extraTokens = amount - balance;
            uint fundsReceived = IReserve(provider.reserve()).requestFunds(token, extraTokens);
            if (fundsReceived<extraTokens) {
                bytes memory returnData = provider.borrowerManager().functionDelegateCall(
                    abi.encodeWithSignature("delever(address,uint256)", token, extraTokens-fundsReceived)
                );
                fee = abi.decode(returnData, (uint));
                amount-=fee;
            }
            IERC20(token).safeTransfer(msg.sender, amount);
            
            uint totalTokenAmount = totalAssets(token) - fundsReceived;
            uint reserveShares;
            if (totalTokenAmount>0) {
                reserveShares = (tokenData[token].totalShares * fundsReceived) / totalTokenAmount;
            } else {
                reserveShares = fundsReceived;
            }
            tokenData[token].totalShares += reserveShares;
            
            _mint(address(IReserve(provider.reserve())), uint(keccak256(abi.encodePacked(token))), reserveShares, "");
        }
        _updateInterestRate(token);
        emit Withdraw(token, msg.sender, amount, shares, fee);
    }
}
