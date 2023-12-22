// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./ISwapper.sol";
import "./FullMath.sol";
import "./PoolToken.sol";
import "./IPoolSettingsSource.sol";

contract Pool is AccessControl, ReentrancyGuard, PoolToken {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant BALANCER_ROLE = keccak256("BALANCER_ROLE");

    IPoolSettingsSource settingsSourceAddress;

    uint256 public unitPoolTokenPriceInReferenceTokenX96Initial;
    address public referenceTokenAddress;

    struct TokenPosition {
        bool active;
        uint256 targetWeightX128;
        uint256 amount;
    }

    mapping (address => TokenPosition) public tokenPositionsMap;
    address[] public tokenPositionsList;

    address[] public registeredTokensForInvestosList;
    mapping (address => bool) public registeredTokensForInvestorsMap;

    uint public constant MAX_TOKEN_COUNT = 100;
    uint256 public swapTolerancePercent = 100; // means that any swaps are now possible

    constructor(address settingsSource, 
                address referenceTokenA, 
                uint256 initialPriceX96, 
                address firstManager, 
                string memory tokenName, 
                string memory tokenSymbol, 
                uint8 tokenDecimals) PoolToken(tokenName, tokenSymbol, tokenDecimals) { //WHY 96?
        settingsSourceAddress = IPoolSettingsSource(settingsSource);
        _grantRole(DEFAULT_ADMIN_ROLE, firstManager);
        _grantRole(MANAGER_ROLE, firstManager);
        _grantRole(BALANCER_ROLE, firstManager);

        referenceTokenAddress = referenceTokenA;
        unitPoolTokenPriceInReferenceTokenX96Initial = initialPriceX96;
    }

    error UnsupportedToken(address token);
    event Funding(address investor, address inputToken, uint256 inputAmount, uint256 poolTokenMinted);
    error UnconfiguredPool();

    function fund(address token, uint128 amount) public nonReentrant {
        require(amount > 0);
        if(registeredTokensForInvestorsMap[token] != true) {
            revert UnsupportedToken(token);
        }

        if(tokenPositionsList.length == 0) {
            revert UnconfiguredPool();
        }

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        uint poolTokensToIssue = FullMath.mulDiv(swapper().getPrice(token, referenceTokenAddress, amount), uint256(1<<96), getCurrentPoolTokenX96Price());

        bool temporaryPositionOpened = false;
        if(tokenPositionsMap[token].active != true) {
            temporaryPositionOpened = true;
            _enableTokenForManagers(token);
        }

        tokenPositionsMap[token].amount += amount;
        _rebalancePool();

        if(temporaryPositionOpened) {
            _disableTokenForManagers(token);
        }
        
        super.mint(msg.sender, poolTokensToIssue);
        emit Funding(msg.sender, token, amount, poolTokensToIssue);
    }
   
    event TokenSoldForWithdrawing(address token, uint amount);
    event Withdrawal(address investor, uint256 poolTokenAmount, uint256 referenceTokenAmount);
    function withdraw(uint amount) public  nonReentrant {

        uint256 shareX96 = FullMath.mulDiv(amount, 1<<96, totalSupply());
        super.burnFrom(msg.sender, amount);

        uint256 collectedRefTokenAmount = 0;
        for(uint i = 0; i < tokenPositionsList.length; i ++) {
            address tokenContractAddress = tokenPositionsList[i];
            uint256 requiredTokenAmount = FullMath.mulDiv(tokenPositionsMap[tokenContractAddress].amount, shareX96, 1<<96);
            if(requiredTokenAmount == 0) {
                continue;
            }

            SafeERC20.safeApprove(IERC20(tokenContractAddress), address(swapper()), 0);
            SafeERC20.safeApprove(IERC20(tokenContractAddress), address(swapper()), requiredTokenAmount);
            // uint256 balanceBefore = IERC20(tokenContractAddress).balanceOf(address(this));
            uint256 outputReferenceTokenAmount = swapper().swapSendExact(tokenContractAddress, referenceTokenAddress, requiredTokenAmount, 0); //TODO check for output amount
            //check the correct amount was spent
            // require(IERC20(tokenContractAddress).balanceOf(address(this)) - balanceBefore == requiredTokenAmount, "Balance after swapping does not match");
            // require(IERC20(tokenContractAddress).allowance(address(this), swapper) == 0, "Resulting allowance is not 0");

            collectedRefTokenAmount += outputReferenceTokenAmount;
            tokenPositionsMap[tokenContractAddress].amount -= requiredTokenAmount;
            emit TokenSoldForWithdrawing(tokenContractAddress, outputReferenceTokenAmount);
        }
        if(collectedRefTokenAmount > 0) {
            SafeERC20.safeTransfer(IERC20(referenceTokenAddress), msg.sender, collectedRefTokenAmount);
        }
        emit Withdrawal(msg.sender, amount, collectedRefTokenAmount);
    }

    error CanNotChangeInitialPriceOfNonEmptyPool();
    function setInitialPoolTokenPrice(uint256 newPriceX96) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(super.totalSupply() != 0) revert CanNotChangeInitialPriceOfNonEmptyPool();
        unitPoolTokenPriceInReferenceTokenX96Initial = newPriceX96;
    }


    event TokenSoldForBalancing(address token, uint256 amount);
    event TokenBoughtForBalancing(address token, uint256 amount);

    function sellToTargetWeightsToRefToken(uint256 totalPriceInReferenceToken, bool[] memory doNotBuyFlags) private returns (uint256 intermediateRefTokenBalance) {
        for(uint i = 0; i < tokenPositionsList.length; i ++) {
            address tokenContractAddress = registeredTokensForInvestosList[i];
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, tokenPositionsMap[tokenContractAddress].targetWeightX128, 1<<128);
            uint128 requiredTokenAmount = swapper().getPrice(referenceTokenAddress, tokenContractAddress, uint128(requiredTokenAmountInRefToken));
            int256 requiredTokenDelta = int256(uint256(requiredTokenAmount)) - int256(tokenPositionsMap[tokenContractAddress].amount);

            if(requiredTokenDelta >= 0) { 
                doNotBuyFlags[i] = false;
                continue;
            }
            
            SafeERC20.safeApprove(IERC20(tokenContractAddress), address(swapper()), 0);
            SafeERC20.safeApprove(IERC20(tokenContractAddress), address(swapper()), uint256(-requiredTokenDelta));
            uint256 outputReferenceTokenAmount = swapper().swapSendExact(tokenContractAddress, referenceTokenAddress, uint256(-requiredTokenDelta), requiredTokenAmountInRefToken * (100-swapTolerancePercent)/100);
            intermediateRefTokenBalance += outputReferenceTokenAmount;
            tokenPositionsMap[tokenContractAddress].amount -= uint256(-requiredTokenDelta);
            emit TokenSoldForBalancing(tokenContractAddress, uint256(-requiredTokenDelta));
            doNotBuyFlags[i] = true;
        }
    }

    function buyToTargetWeightsFromRefToken(uint256 totalPriceInReferenceToken, bool[] memory doNotBuyFlags, uint256 intermediateRefTokenBalance) private {
        for(uint i = 0; i < tokenPositionsList.length; i ++) {
            if(doNotBuyFlags[i]) {
                continue;
            }
            address tokenContractAddress = registeredTokensForInvestosList[i];
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, tokenPositionsMap[tokenContractAddress].targetWeightX128, 1<<128);
            uint128 currentTokenAmountInRefToken = swapper().getPrice(tokenContractAddress, referenceTokenAddress, uint128(tokenPositionsMap[tokenContractAddress].amount));
            uint128 requiredTokenAmount = swapper().getPrice(referenceTokenAddress, tokenContractAddress, uint128(requiredTokenAmountInRefToken));

            int256 requiredTokenDeltaInRefToken = int256(uint256(requiredTokenAmountInRefToken)) - int256(uint256(currentTokenAmountInRefToken));
            if(requiredTokenDeltaInRefToken <= 0) {
                continue;
            }
            uint256 amountToPayInRefToken = uint256(requiredTokenDeltaInRefToken);
            if(intermediateRefTokenBalance < amountToPayInRefToken) {
                amountToPayInRefToken = intermediateRefTokenBalance;
            }
            uint outAmount =  swapper().swapSendExact(referenceTokenAddress, tokenContractAddress, amountToPayInRefToken, requiredTokenAmount * (100-swapTolerancePercent)/100);
            
            tokenPositionsMap[tokenContractAddress].amount += outAmount;

            intermediateRefTokenBalance -= amountToPayInRefToken;
            emit TokenBoughtForBalancing(tokenContractAddress, outAmount);
        }
        require(intermediateRefTokenBalance == 0);
    }

    function _rebalancePool() private { 
        uint totalPriceInReferenceToken = getTotalPoolPriceInReferenceToken();
        bool[] memory doNotBuyFlags = new bool[](registeredTokensForInvestosList.length);

        //selling to reference token
        uint intermediateRefTokenBalance = sellToTargetWeightsToRefToken(totalPriceInReferenceToken, doNotBuyFlags);
        
        //buying from reference token
        if(intermediateRefTokenBalance > 0) {
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), address(swapper()), 0);
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), address(swapper()), intermediateRefTokenBalance);
            buyToTargetWeightsFromRefToken(totalPriceInReferenceToken, doNotBuyFlags, intermediateRefTokenBalance);
        }
    }

    function rebalancePool() public onlyRole(BALANCER_ROLE)  nonReentrant { 
        _rebalancePool();
    }

    event TokenEnabledForInvestors(address tokenAddress);
    error MaxEnabledTokensForInvestorsCountExceeded();

    function _enableTokenForInvestors(address tokenAddress) private {
        if(registeredTokensForInvestorsMap[tokenAddress] == true) {
            return;
        }

        if(registeredTokensForInvestosList.length > MAX_TOKEN_COUNT) revert MaxEnabledTokensForInvestorsCountExceeded();
        registeredTokensForInvestosList.push(tokenAddress);
        registeredTokensForInvestorsMap[tokenAddress] = true;
        emit TokenEnabledForInvestors(tokenAddress);
    }

    function enableTokenForInvestors(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _enableTokenForInvestors(tokenAddress);
    }

    event TokenDisabledForInvestors(address tokenAddress);

    function disableTokenForInvestors(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(registeredTokensForInvestorsMap[tokenAddress] == false) {
            return;
        }
        for(uint i = 1; i < registeredTokensForInvestosList.length; i++) {
            if(registeredTokensForInvestosList[i] == tokenAddress) {
                registeredTokensForInvestosList[i] = registeredTokensForInvestosList[registeredTokensForInvestosList.length - 1];
                registeredTokensForInvestosList.pop();
                break;
            }
        }
        delete registeredTokensForInvestorsMap[tokenAddress];
        emit TokenDisabledForInvestors(tokenAddress);
    }

    error CannotRemoveTokenWithNonZeroBalance(address token);
    event TokenDisabledForManagers(address tokenAddress);

    function disableTokenForManagers(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _disableTokenForManagers(tokenAddress);
    }

    function _disableTokenForManagers(address tokenAddress) private {
        if(tokenPositionsMap[tokenAddress].amount != 0) {
            revert CannotRemoveTokenWithNonZeroBalance(tokenAddress);
        }
        if(tokenPositionsMap[tokenAddress].active == false) return;
        delete tokenPositionsMap[tokenAddress];
        for(uint i = 0; i < tokenPositionsList.length; i++) {
            if(tokenPositionsList[i] == tokenAddress) {
                tokenPositionsList[i] = tokenPositionsList[tokenPositionsList.length - 1];
                tokenPositionsList.pop();
                break;
            }
        }
        emit TokenDisabledForManagers(tokenAddress);
    }

    event TokenEnabledForManagers(address tokenAddress);
    error MaxEnabledTokensForManagersCountExceeded();

    function _enableTokenForManagers(address tokenAddress) private {
        if(tokenPositionsMap[tokenAddress].active == true) {
            return;
        }

        if(tokenPositionsList.length > MAX_TOKEN_COUNT) revert MaxEnabledTokensForManagersCountExceeded();
        tokenPositionsList.push(tokenAddress);
        tokenPositionsMap[tokenAddress].active = true;
        if(tokenPositionsList.length == 1) {
            tokenPositionsMap[tokenAddress].targetWeightX128 = 1<<128;
        }
    }

    function enableTokenForManagers(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _enableTokenForManagers(tokenAddress);
        emit TokenEnabledForManagers(tokenAddress);
    }

    error WeightsListLengthDoesNotMatchPositionsListLength();
    error WeightsListTotalIsNotEqualToOne();
    function setWeights(uint256[] calldata orderedTokenWeightsX128) public onlyRole(MANAGER_ROLE) {
        if(tokenPositionsList.length != orderedTokenWeightsX128.length) {
            revert WeightsListLengthDoesNotMatchPositionsListLength();
        }
        uint256 checkSum = 0;
        for(uint i = 0; i < orderedTokenWeightsX128.length; i ++) {
            checkSum += orderedTokenWeightsX128[i];
        }
        if(checkSum != 1<<128) {
            revert WeightsListTotalIsNotEqualToOne();
        }

        for(uint i = 0; i < tokenPositionsList.length; i++) {
            tokenPositionsMap[tokenPositionsList[i]].targetWeightX128 = orderedTokenWeightsX128[i];
        }
    }
    
    // ############################### views ###############################

    function swapper() private view returns (ISwapper) {
        return settingsSourceAddress.getPoolSettings().swapper;
    }

    function getEnabledForInvestorsTokensList() public view returns (address[] memory){
        return registeredTokensForInvestosList;
    }

    function getPoolTokensList() public view returns (address[] memory){
        return tokenPositionsList;
    }

    function getTotalPoolPriceInReferenceToken() public view returns(uint256) {
        uint256 t = 0;

        for(uint i = 0; i < tokenPositionsList.length; i ++) {
            t += swapper().getPrice(tokenPositionsList[i], referenceTokenAddress, uint128(tokenPositionsMap[tokenPositionsList[i]].amount));
        }
        return t;
    }

    function getCurrentPoolTokenX96Price() public view returns(uint256) {
        uint supl = super.totalSupply();
        if(supl == 0) return unitPoolTokenPriceInReferenceTokenX96Initial;
        return FullMath.mulDiv(getTotalPoolPriceInReferenceToken(), uint256(1<<96), supl);
    }

    function getInvestorSharePriceInReferenceToken(address investorAddress) public view returns(uint256) {
        uint poolTokenAmount = super.balanceOf(investorAddress);
        if(poolTokenAmount == 0) return 0;

        return FullMath.mulDiv(poolTokenAmount, getCurrentPoolTokenX96Price(), uint256(1<<96));
    }

    struct TokenPositionInfo {
        address token;
        uint256 targetWeightX128;
        uint256 currentWeightX128;
        uint256 amount;
        uint256 valueInRefTokens;
    }

    function getPoolPositionsInfo() public view returns (TokenPositionInfo[] memory){
        TokenPositionInfo[] memory ret = new TokenPositionInfo[](tokenPositionsList.length);
        uint256 totalPriceInRefToken = getTotalPoolPriceInReferenceToken();
        for(uint i = 0; i < tokenPositionsList.length; i ++) {
            address tkAddress = tokenPositionsList[i];
            ret[i].token = tokenPositionsList[i];
            ret[i].targetWeightX128 = tokenPositionsMap[tkAddress].targetWeightX128;
            ret[i].amount = tokenPositionsMap[tkAddress].amount;
            ret[i].valueInRefTokens = swapper().getPrice(tkAddress, referenceTokenAddress, uint128(ret[i].amount));
            ret[i].currentWeightX128 = totalPriceInRefToken > 0 ? FullMath.mulDiv(ret[i].valueInRefTokens, 1<<128, totalPriceInRefToken): 0;
        }
        return ret;
    }
}

