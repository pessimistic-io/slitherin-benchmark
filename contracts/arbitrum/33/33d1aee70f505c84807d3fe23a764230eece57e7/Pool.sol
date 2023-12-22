// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ISwapper.sol";
import "./FullMath.sol";
import "./PoolToken.sol";
contract Pool is Pausable, AccessControl {

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");


    address public swapper;
    PoolToken public poolToken;


    uint256 public unitPoolTokenPriceInReferenceTokenX96Initial;
    address public referenceTokenAddress;

    mapping (address => uint256) public tokenBalances;
    address[] public registeredTokensList;
    mapping (address => bool) public registeredTokensMap;

    uint public constant MAX_TOKEN_COUNT = 100;

    constructor(address referenceTokenA, uint256 initialPriceX96, address firstManager, string memory tokenName, string memory tokenSymbol) { //WHY 96?
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, firstManager);

        referenceTokenAddress = referenceTokenA;
        unitPoolTokenPriceInReferenceTokenX96Initial = initialPriceX96;
        poolToken = new PoolToken(tokenName, tokenSymbol);
    }
    function setSwapper(address newSwapper) public onlyRole(DEFAULT_ADMIN_ROLE) {
        swapper = newSwapper;
    }

    error MaxTokenCountExceeded();

    function fund(address token, uint128 amount) public { //
        require(amount > 0);

        _registerToken(token);

        uint amountInReferenceTokens = ISwapper(swapper).getPrice(token, referenceTokenAddress, amount);
        uint poolTokensToIssue = FullMath.mulDiv(amountInReferenceTokens, uint256(1<<96), getCurrentPoolTokenX96Price());
        poolToken.mint(msg.sender, poolTokensToIssue);
        tokenBalances[token] += amount;

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
    }
   
    event TokenSoldForWithdrawing(address token, uint amount);
    function withdraw(address to, uint amountPoolToken) public {
        uint256 shareX96 = FullMath.mulDiv(amountPoolToken, 1<<96, poolToken.totalSupply());
        uint256 collectedRefTokenAmount = 0;
        for(uint i = 0; i < registeredTokensList.length; i ++) {
            uint256 requiredTokenAmount = FullMath.mulDiv(tokenBalances[registeredTokensList[i]], shareX96, 1<<96);
            if(requiredTokenAmount != 0) {
                SafeERC20.safeApprove(IERC20(registeredTokensList[i]), swapper, 0);
                SafeERC20.safeApprove(IERC20(registeredTokensList[i]), swapper, requiredTokenAmount);
                uint256 outputReferenceTokenAmount = ISwapper(swapper).swapSendExact(registeredTokensList[i], referenceTokenAddress, requiredTokenAmount, 0); //TODO check for output amount
                collectedRefTokenAmount += outputReferenceTokenAmount;
                tokenBalances[registeredTokensList[i]] -= requiredTokenAmount;
                emit TokenSoldForBalancing(registeredTokensList[i], outputReferenceTokenAmount);
            }
        }
        if(collectedRefTokenAmount > 0) {
            SafeERC20.safeTransfer(IERC20(referenceTokenAddress), to, collectedRefTokenAmount);
        }
        poolToken.burnFrom(msg.sender, amountPoolToken);
    }

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

    error CanNotChangeInitialPriceOfNonEmptyPool();
    function setInitialPoolTokenPrice(uint256 newPriceX96) public onlyRole(MANAGER_ROLE) {
        if(poolToken.totalSupply() != 0) revert CanNotChangeInitialPriceOfNonEmptyPool();
        unitPoolTokenPriceInReferenceTokenX96Initial = newPriceX96;
    }

    error SharesListLengthDoesNotMatchTokensListLength();
    error SharesListSomeNotEqualOne();

    event TokenSoldForBalancing(address token, uint256 amount);
    event TokenBoughtForBalancing(address token, uint256 amount);

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
        for(uint i = 0; i < sharesX128.length; i ++) {
            uint256 requiredTokenAmountInRefToken = FullMath.mulDiv(totalPriceInReferenceToken, sharesX128[i], 1<<128);
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
    // [85070591730234615865843651857942052864,85070591730234615865843651857942052864,0,170141183460469231731687303715884105728]
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

