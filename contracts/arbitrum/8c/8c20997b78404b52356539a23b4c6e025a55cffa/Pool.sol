// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ISwapper.sol";
import "./FullMath.sol";

contract Pool is Pausable, AccessControl {

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");


    address public swapper;

    mapping (address => uint256) poolTokenInvestorsBalances;
    uint256 poolTokenSupply;
    uint256 poolPriceInExternalReferenceToken;
    uint256 unitPoolTokenPriceInReferenceTokenX96;
    address referenceTokenAddress;

    mapping (address => uint128) tokensBalances;
    address[] tokensList;

    uint public constant MAX_TOKEN_COUNT = 100;

    constructor(address referenceTokenA, uint256 initialPriceX96, address firstManager) { //WHY 96?
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, firstManager);

        referenceTokenAddress = referenceTokenA;
        unitPoolTokenPriceInReferenceTokenX96 = initialPriceX96;
    }
    function setSwapper(address newSwapper) public onlyRole(DEFAULT_ADMIN_ROLE) {
        swapper = newSwapper;
    }

    error MaxTokenCountExceeded();

    function fund(address token, uint128 amount) public { //
        require(amount > 0);

        if(tokensBalances[token] == 0) {
            if(tokensList.length > MAX_TOKEN_COUNT) revert MaxTokenCountExceeded();
            tokensList.push(token);
        }

        if(!hasRole(INVESTOR_ROLE, msg.sender))
            _grantRole(INVESTOR_ROLE, msg.sender);

        uint amountInReferenceTokens = ISwapper(swapper).getPrice(token, referenceTokenAddress, amount);
        uint poolTokensToIssue = FullMath.mulDiv(amountInReferenceTokens, uint256(1<<96), unitPoolTokenPriceInReferenceTokenX96);
        poolTokenSupply += poolTokensToIssue;
        poolTokenInvestorsBalances[msg.sender] += poolTokensToIssue;

        tokensBalances[token] += amount;

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
    }

    function withdraw(address to, address token, uint amount) public onlyRole(INVESTOR_ROLE) {
        revert("unimplemented");
        //burn pool token here, update price, change poolTokenInvestorsBalances 

        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }

    function getTotalPoolPriceInReferenceToken() public view returns(uint256) {
        uint256 t = 0;

        for(uint i = 0; i < tokensList.length; i ++) {
            t += ISwapper(swapper).getPrice(tokensList[i], referenceTokenAddress, tokensBalances[tokensList[i]]);
        }
        return t;
    }

    function getCurrentPoolTokenX96Price() public view returns(uint256) {
        if(poolTokenSupply == 0) return 0;
        return FullMath.mulDiv(getTotalPoolPriceInReferenceToken(), uint256(1<<96), poolTokenSupply);
    }

    function getInvestorSharePriceInReferenceToken() public view returns(uint256) {
        uint poolTokenAmount = poolTokenInvestorsBalances[msg.sender];
        if(poolTokenAmount == 0) return 0;

        return FullMath.mulDiv(poolTokenAmount, getCurrentPoolTokenX96Price(), uint256(1<<96));
    }

    error CanNotChangeInitialPriceOnNonEmptyPool();
    function setInitialPoolTokenPrice(uint256 newPriceX96) public onlyRole(MANAGER_ROLE) {
        if(poolTokenSupply != 0) revert CanNotChangeInitialPriceOnNonEmptyPool();
        unitPoolTokenPriceInReferenceTokenX96 = newPriceX96;
    }

    function updatePoolTokenPrice() public {
        unitPoolTokenPriceInReferenceTokenX96 = getCurrentPoolTokenX96Price();
    }

    error SharesListLengthDoesNotMatchTokensListLength();
    error SharesListSomeNotEqualOne();
    function rebalancePool(uint256[] calldata sharesX128) public onlyRole(MANAGER_ROLE){ // Most stupid and obvious implementation
        if(tokensList.length != sharesX128.length) {
            revert SharesListLengthDoesNotMatchTokensListLength();
        }
        uint256 checkSum = 0;
        for(uint i = 0; i < sharesX128.length; i ++) {
            checkSum += sharesX128[i];
        }
        if(checkSum != 1<<128) {
            revert SharesListSomeNotEqualOne();
        }

        uint totalPriceInReferenceToken = getTotalPoolPriceInReferenceToken();

        uint percent = 97;

        uint intermediateRefTokenBalance = 0;

        //selling to reference token
        for(uint i = 0; i < sharesX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, sharesX128[i], 1<<128);
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, tokensList[i], uint128(requiredTokenAmountInRefToken));
            int256 requiredTokenDelta = int256(uint256(requiredTokenAmount)) - int256(uint256(tokensBalances[tokensList[i]]));
            if(requiredTokenDelta < 0) {
                SafeERC20.safeApprove(IERC20(tokensList[i]), swapper, uint256(-requiredTokenDelta));
                uint256 outputReferenceTokenAmount = ISwapper(swapper).swapSendExact(tokensList[i], referenceTokenAddress, uint256(-requiredTokenDelta), requiredTokenAmountInRefToken * percent/100);
                intermediateRefTokenBalance += outputReferenceTokenAmount;
            }
        }

        if(intermediateRefTokenBalance > 0) {
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), swapper, intermediateRefTokenBalance);
        }

        //buying from reference token
        for(uint i = 0; i < sharesX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, sharesX128[i], 1<<128);
            uint128 currentTokenAmountInRefToken = ISwapper(swapper).getPrice(tokensList[i], referenceTokenAddress, uint128(tokensBalances[tokensList[i]]));
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, tokensList[i], uint128(requiredTokenAmountInRefToken));

            int256 requiredTokenDeltaInRefToken = int256(uint256(requiredTokenAmountInRefToken)) - int256(uint256(currentTokenAmountInRefToken));
            if(requiredTokenDeltaInRefToken > 0) {
                uint256 amountToPayInRefToken = uint256(requiredTokenDeltaInRefToken);
                if(intermediateRefTokenBalance < amountToPayInRefToken) {
                    amountToPayInRefToken = intermediateRefTokenBalance;
                }
                ISwapper(swapper).swapSendExact(referenceTokenAddress, tokensList[i], amountToPayInRefToken, requiredTokenAmount * percent/100);
                intermediateRefTokenBalance -= amountToPayInRefToken;
            }
        }
        require(intermediateRefTokenBalance == 0);
    }
}

