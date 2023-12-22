// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ISwapper.sol";
import "./FullMath.sol";
import "./PoolToken.sol";
contract Pool is AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    address public swapper;
    PoolToken public poolToken;

    uint256 public unitPoolTokenPriceInReferenceTokenX96Initial;
    address public referenceTokenAddress;

    mapping (address => uint256) public tokenBalances;
    address[] public registeredTokensList;
    mapping (address => bool) public registeredTokensMap;

    uint public constant MAX_TOKEN_COUNT = 100;
    uint256 public swapTolerancePercent = 3;

    constructor(address referenceTokenA, uint256 initialPriceX96, address firstManager, address ISwapperContract, string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) { //WHY 96?
        _grantRole(DEFAULT_ADMIN_ROLE, firstManager);
        _grantRole(MANAGER_ROLE, firstManager);

        referenceTokenAddress = referenceTokenA;
        _registerToken(referenceTokenA);
        unitPoolTokenPriceInReferenceTokenX96Initial = initialPriceX96;
        poolToken = new PoolToken(tokenName, tokenSymbol, tokenDecimals);
        swapper = ISwapperContract;
    }

    error MaxTokenCountExceeded();
    error UnsupportedToken(address token);
    event Funding(address investor, address inputToken, uint256 inputAmount, uint256 poolTokenMinted);
    function fund(address token, uint128 amount) public {
        require(amount > 0);
        if(registeredTokensMap[token] != true) {
            revert UnsupportedToken(token);
        }
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        uint amountInReferenceTokens = ISwapper(swapper).getPrice(token, referenceTokenAddress, amount);
        uint poolTokensToIssue = FullMath.mulDiv(amountInReferenceTokens, uint256(1<<96), getCurrentPoolTokenX96Price());
        poolToken.mint(msg.sender, poolTokensToIssue);
        tokenBalances[token] += amount;

        emit Funding(msg.sender, token, amount, poolTokensToIssue);


        //rebalance here?
    }
   
    event TokenSoldForWithdrawing(address token, uint amount);
    event Withdrawal(address investor, uint256 poolTokenAmount, uint256 referenceTokenAmount);
    function withdraw(uint amountPoolToken) public {

        uint256 shareX96 = FullMath.mulDiv(amountPoolToken, 1<<96, poolToken.totalSupply());
        poolToken.burnFrom(msg.sender, amountPoolToken);

        uint256 collectedRefTokenAmount = 0;
        for(uint i = 0; i < registeredTokensList.length; i ++) {
            address tokenContractAddress = registeredTokensList[i];
            uint256 requiredTokenAmount = FullMath.mulDiv(tokenBalances[tokenContractAddress], shareX96, 1<<96);
            if(requiredTokenAmount == 0) {
                continue;
            }

            SafeERC20.safeApprove(IERC20(tokenContractAddress), swapper, requiredTokenAmount);
            uint256 balanceBefore = IERC20(tokenContractAddress).balanceOf(address(this));
            uint256 outputReferenceTokenAmount = ISwapper(swapper).swapSendExact(tokenContractAddress, referenceTokenAddress, requiredTokenAmount, 0); //TODO check for output amount
            //check the correct amount was spent
            require(IERC20(tokenContractAddress).balanceOf(address(this)) - balanceBefore == requiredTokenAmount, "Balance after swapping does not match");
            require(IERC20(tokenContractAddress).allowance(address(this), swapper) == 0, "Resulting allowance is not 0");

            collectedRefTokenAmount += outputReferenceTokenAmount;
            tokenBalances[tokenContractAddress] -= requiredTokenAmount;
            emit TokenSoldForWithdrawing(tokenContractAddress, outputReferenceTokenAmount);
        }
        if(collectedRefTokenAmount > 0) {
            SafeERC20.safeTransfer(IERC20(referenceTokenAddress), msg.sender, collectedRefTokenAmount);
            emit Withdrawal(msg.sender, amountPoolToken, collectedRefTokenAmount);
        }
    }

    error CanNotChangeInitialPriceOfNonEmptyPool();
    function setInitialPoolTokenPrice(uint256 newPriceX96) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(poolToken.totalSupply() != 0) revert CanNotChangeInitialPriceOfNonEmptyPool();
        unitPoolTokenPriceInReferenceTokenX96Initial = newPriceX96;
    }

    error SharesListLengthDoesNotMatchTokensListLength();
    error SharesListSomeNotEqualOne();

    event TokenSoldForBalancing(address token, uint256 amount);
    event TokenBoughtForBalancing(address token, uint256 amount);

    function rebalancePool(uint256[] calldata orderedTokenWeightsX128) public onlyRole(MANAGER_ROLE){ // Most stupid and obvious implementation
        if(registeredTokensList.length != orderedTokenWeightsX128.length) {
            revert SharesListLengthDoesNotMatchTokensListLength();
        }
        uint256 checkSum = 0;
        for(uint i = 0; i < orderedTokenWeightsX128.length; i ++) {
            checkSum += orderedTokenWeightsX128[i];
        }
        if(checkSum != 1<<128) {
            revert SharesListSomeNotEqualOne();
        }

        uint totalPriceInReferenceToken = getTotalPoolPriceInReferenceToken();

        uint percent = 0;

        uint intermediateRefTokenBalance = 0;

        //selling to reference token
        for(uint i = 0; i < orderedTokenWeightsX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, orderedTokenWeightsX128[i], 1<<128);
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, registeredTokensList[i], uint128(requiredTokenAmountInRefToken));
            int256 requiredTokenDelta = int256(uint256(requiredTokenAmount)) - int256(tokenBalances[registeredTokensList[i]]);
            if(requiredTokenDelta < 0) {
                SafeERC20.safeApprove(IERC20(registeredTokensList[i]), swapper, 0);
                SafeERC20.safeApprove(IERC20(registeredTokensList[i]), swapper, uint256(-requiredTokenDelta));
                uint256 outputReferenceTokenAmount = ISwapper(swapper).swapSendExact(registeredTokensList[i], referenceTokenAddress, uint256(-requiredTokenDelta), requiredTokenAmountInRefToken * percent/100);
                intermediateRefTokenBalance += outputReferenceTokenAmount;
                tokenBalances[registeredTokensList[i]] -= uint256(-requiredTokenDelta);
                emit TokenSoldForBalancing(registeredTokensList[i], uint256(-requiredTokenDelta));
            }
        }

        if(intermediateRefTokenBalance > 0) {
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), swapper, 0);
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), swapper, intermediateRefTokenBalance);
        }

        //buying from reference token
        for(uint i = 0; i < orderedTokenWeightsX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, orderedTokenWeightsX128[i], 1<<128);
            uint128 currentTokenAmountInRefToken = ISwapper(swapper).getPrice(registeredTokensList[i], referenceTokenAddress, uint128(tokenBalances[registeredTokensList[i]]));
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, registeredTokensList[i], uint128(requiredTokenAmountInRefToken));

            int256 requiredTokenDeltaInRefToken = int256(uint256(requiredTokenAmountInRefToken)) - int256(uint256(currentTokenAmountInRefToken));
            if(requiredTokenDeltaInRefToken > 0) {
                uint256 amountToPayInRefToken = uint256(requiredTokenDeltaInRefToken);
                if(intermediateRefTokenBalance < amountToPayInRefToken) {
                    amountToPayInRefToken = intermediateRefTokenBalance;
                }
                uint outAmount =  ISwapper(swapper).swapSendExact(referenceTokenAddress, registeredTokensList[i], amountToPayInRefToken, requiredTokenAmount * percent/100);
                tokenBalances[registeredTokensList[i]] += outAmount;

                intermediateRefTokenBalance -= amountToPayInRefToken;
                emit TokenBoughtForBalancing(registeredTokensList[i], outAmount);
            }
        }
        require(intermediateRefTokenBalance == 0);
    }

    event TokenRegistered(address tokenAddress);

    function _registerToken(address tokenAddress) private {
        if(registeredTokensMap[tokenAddress] == false) {
            if(registeredTokensList.length > MAX_TOKEN_COUNT) revert MaxTokenCountExceeded();
            registeredTokensList.push(tokenAddress);
            registeredTokensMap[tokenAddress] = true;
            emit TokenRegistered(tokenAddress);
        }
    }

    function registerToken(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _registerToken(tokenAddress);
    }

    function setSwapper(address newSwapper) public onlyRole(DEFAULT_ADMIN_ROLE) {
        swapper = newSwapper;
    }


    //views
    function getTotalPoolPriceInReferenceToken() public view returns(uint256) {
        uint256 t = 0;

        for(uint i = 0; i < registeredTokensList.length; i ++) {
            t += ISwapper(swapper).getPrice(registeredTokensList[i], referenceTokenAddress, uint128(tokenBalances[registeredTokensList[i]]));
        }
        return t;
    }

    function getCurrentPoolTokenX96Price() public view returns(uint256) {
        uint supl = poolToken.totalSupply();
        if(supl == 0) return unitPoolTokenPriceInReferenceTokenX96Initial;
        return FullMath.mulDiv(getTotalPoolPriceInReferenceToken(), uint256(1<<96), supl);
    }

    function getInvestorSharePriceInReferenceToken(address investorAddress) public view returns(uint256) {
        uint poolTokenAmount = poolToken.balanceOf(investorAddress);
        if(poolTokenAmount == 0) return 0;

        return FullMath.mulDiv(poolTokenAmount, getCurrentPoolTokenX96Price(), uint256(1<<96));
    }
}

