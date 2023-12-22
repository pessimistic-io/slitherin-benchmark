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

    mapping (address => uint256) public poolTokenInvestorsBalances;

    uint256 public poolTokenSupply;
    uint256 public unitPoolTokenPriceInReferenceTokenX96;
    address public referenceTokenAddress;

    mapping (address => uint128) public tokensBalances;
    address[] public registeredTokensList;
    mapping (address => bool) public registeredTokensMap;

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

        _registerToken(token);

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

        for(uint i = 0; i < registeredTokensList.length; i ++) {
            t += ISwapper(swapper).getPrice(registeredTokensList[i], referenceTokenAddress, tokensBalances[registeredTokensList[i]]);
        }
        return t;
    }

    function getCurrentPoolTokenX96Price() public view returns(uint256) {
        if(poolTokenSupply == 0) return 0;
        return FullMath.mulDiv(getTotalPoolPriceInReferenceToken(), uint256(1<<96), poolTokenSupply);
    }

    function getInvestorSharePriceInReferenceToken(address investorAddress) public view returns(uint256) {
        uint poolTokenAmount = poolTokenInvestorsBalances[investorAddress];
        if(poolTokenAmount == 0) return 0;

        return FullMath.mulDiv(poolTokenAmount, getCurrentPoolTokenX96Price(), uint256(1<<96));
    }

    error CanNotChangeInitialPriceOfNonEmptyPool();
    function setInitialPoolTokenPrice(uint256 newPriceX96) public onlyRole(MANAGER_ROLE) {
        if(poolTokenSupply != 0) revert CanNotChangeInitialPriceOfNonEmptyPool();
        unitPoolTokenPriceInReferenceTokenX96 = newPriceX96;
    }

    function updatePoolTokenPrice() public {
        unitPoolTokenPriceInReferenceTokenX96 = getCurrentPoolTokenX96Price();
    }

    error SharesListLengthDoesNotMatchTokensListLength();
    error SharesListSomeNotEqualOne();
    function rebalancePool(uint256[] calldata sharesX128) public onlyRole(MANAGER_ROLE){ // Most stupid and obvious implementation
        if(registeredTokensList.length != sharesX128.length) {
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

        uint percent = 0;

        uint intermediateRefTokenBalance = 0;

        //selling to reference token
        for(uint i = 0; i < sharesX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, sharesX128[i], 1<<128);
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, registeredTokensList[i], uint128(requiredTokenAmountInRefToken));
            int256 requiredTokenDelta = int256(uint256(requiredTokenAmount)) - int256(uint256(tokensBalances[registeredTokensList[i]]));
            if(requiredTokenDelta < 0) {
                SafeERC20.safeApprove(IERC20(registeredTokensList[i]), swapper, uint256(-requiredTokenDelta));
                uint256 outputReferenceTokenAmount = ISwapper(swapper).swapSendExact(registeredTokensList[i], referenceTokenAddress, uint256(-requiredTokenDelta), requiredTokenAmountInRefToken * percent/100);
                intermediateRefTokenBalance += outputReferenceTokenAmount;
            }
        }

        if(intermediateRefTokenBalance > 0) {
            SafeERC20.safeApprove(IERC20(referenceTokenAddress), swapper, intermediateRefTokenBalance);
        }

        //buying from reference token
        for(uint i = 0; i < sharesX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, sharesX128[i], 1<<128);
            uint128 currentTokenAmountInRefToken = ISwapper(swapper).getPrice(registeredTokensList[i], referenceTokenAddress, uint128(tokensBalances[registeredTokensList[i]]));
            uint128 requiredTokenAmount = ISwapper(swapper).getPrice(referenceTokenAddress, registeredTokensList[i], uint128(requiredTokenAmountInRefToken));

            int256 requiredTokenDeltaInRefToken = int256(uint256(requiredTokenAmountInRefToken)) - int256(uint256(currentTokenAmountInRefToken));
            if(requiredTokenDeltaInRefToken > 0) {
                uint256 amountToPayInRefToken = uint256(requiredTokenDeltaInRefToken);
                if(intermediateRefTokenBalance < amountToPayInRefToken) {
                    amountToPayInRefToken = intermediateRefTokenBalance;
                }
                ISwapper(swapper).swapSendExact(referenceTokenAddress, registeredTokensList[i], amountToPayInRefToken, requiredTokenAmount * percent/100);
                intermediateRefTokenBalance -= amountToPayInRefToken;
            }
        }
        require(intermediateRefTokenBalance == 0);
    }
    
    function _registerToken(address tokenAddress) private {
        if(registeredTokensMap[tokenAddress] == false) {
            if(registeredTokensList.length > MAX_TOKEN_COUNT) revert MaxTokenCountExceeded();
            registeredTokensList.push(tokenAddress);
            registeredTokensMap[tokenAddress] = true;
        }
    }

    function registerToken(address tokenAddress) public onlyRole(MANAGER_ROLE) {
        _registerToken(tokenAddress);
    }
}

